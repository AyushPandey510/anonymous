use crate::{
    app::AppState,
    auth::AuthUser,
    error::{ApiError, ApiResult},
    models::Message,
    moderation::ModerationJob,
};
use axum::{
    extract::{
        ws::{Message as WsMessage, WebSocket},
        Path, State, WebSocketUpgrade,
    },
    response::Response,
    routing::{get, post},
    Json, Router,
};
use chrono::{Duration, Utc};
use serde::Deserialize;
use std::sync::Arc;
use utoipa::ToSchema;
use uuid::Uuid;
use validator::Validate;

#[derive(Debug, Deserialize, ToSchema, Validate)]
pub struct SendMessageRequest {
    pub session_id: Uuid,
    #[validate(length(min = 1, max = 2000))]
    pub content: String,
    pub reply_to: Option<Uuid>,
    pub poll_options: Option<Vec<String>>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct VoteRequest {
    pub session_id: Uuid,
    pub option_index: i32,
}

fn validate_poll_options(options: &[String]) -> ApiResult<()> {
    let unique: std::collections::HashSet<_> =
        options.iter().map(|s| s.trim().to_lowercase()).collect();
    if !(2..=6).contains(&options.len())
        || unique.len() != options.len()
        || options
            .iter()
            .any(|s| s.trim().is_empty() || s.chars().count() > 100)
    {
        return Err(ApiError::Validation(
            "Provide 2-6 distinct poll options, up to 100 characters each".into(),
        ));
    }
    Ok(())
}

#[derive(Debug, Deserialize, ToSchema, Validate)]
pub struct ReportMessageRequest {
    #[validate(length(min = 2, max = 120))]
    pub reason: String,
}

#[derive(Debug, Deserialize, ToSchema, Validate)]
pub struct ReactRequest {
    pub session_id: Uuid,
    #[validate(length(min = 1, max = 16))]
    pub emoji: String,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route(
            "/spaces/:space_id/messages",
            get(list_messages).post(send_message),
        )
        .route("/messages/:message_id/report", post(report_message))
        .route("/messages/:message_id/delete", post(delete_message))
        .route("/messages/:message_id/react", post(react_message))
        .route("/messages/:message_id/vote", post(vote_poll))
        .route("/ws/spaces/:space_id", get(websocket))
}

#[utoipa::path(get, path = "/spaces/{space_id}/messages", responses((status = 200, body = Vec<Message>)))]
pub async fn list_messages(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(space_id): Path<Uuid>,
) -> ApiResult<Json<Vec<Message>>> {
    let has_session = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM activity.sessions WHERE user_id = $1 AND space_id = $2 AND status IN ('active', 'grace') AND expires_at > now())",
    )
    .bind(user_id)
    .bind(space_id)
    .fetch_one(&state.pool)
    .await?;
    if !has_session {
        return Err(ApiError::Forbidden);
    }

    let messages = sqlx::query_as::<_, Message>(
        r#"
        SELECT
            m.id, m.space_id, m.anonymous_id, m.content, m.reply_to, m.created_at,
            m.moderation_status::text,
            CASE WHEN m.poll_options IS NOT NULL THEN json_build_object(
                'options', m.poll_options,
                'counts', (SELECT json_agg((SELECT count(*) FROM activity.poll_votes v WHERE v.message_id = m.id AND v.option_index = i)) FROM generate_series(0, jsonb_array_length(m.poll_options)-1) i),
                'selected', (SELECT option_index FROM activity.poll_votes WHERE message_id = m.id AND user_id = $2)
            ) END AS poll,
            r.content AS reply_content,
            COALESCE((
                SELECT json_agg(json_build_object('emoji', agg.emoji, 'count', agg.cnt))
                FROM (
                    SELECT emoji, COUNT(*) AS cnt
                    FROM activity.reactions
                    WHERE message_id = m.id
                    GROUP BY emoji
                ) agg
            ), '[]'::json) AS reactions
        FROM activity.messages m
        LEFT JOIN activity.messages r ON r.id = m.reply_to
        WHERE m.space_id = $1 AND m.deleted_at IS NULL AND m.moderation_status <> 'hidden'
        ORDER BY m.created_at ASC
        LIMIT 100
        "#,
    )
    .bind(space_id)
    .bind(user_id)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(messages))
}

#[utoipa::path(post, path = "/spaces/{space_id}/messages", request_body = SendMessageRequest, responses((status = 200, body = Message)))]
pub async fn send_message(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(space_id): Path<Uuid>,
    Json(payload): Json<SendMessageRequest>,
) -> ApiResult<Json<Message>> {
    payload
        .validate()
        .map_err(|error| ApiError::Validation(error.to_string()))?;
    let anonymous_id =
        active_session_anonymous_id(&state, user_id, space_id, payload.session_id).await?;
    if let Some(options) = &payload.poll_options {
        validate_poll_options(options)?;
        if payload.content.trim().is_empty() || payload.content.chars().count() > 280 {
            return Err(ApiError::Validation(
                "Poll question must be 1-280 characters".into(),
            ));
        }
    }
    let options = payload.poll_options.map(|items| {
        items
            .into_iter()
            .map(|s| s.trim().to_owned())
            .collect::<Vec<_>>()
    });
    let reply_content = if let Some(reply_id) = payload.reply_to {
        Some(validate_reply_target(&state, space_id, reply_id).await?)
    } else {
        None
    };

    let mut message = sqlx::query_as::<_, Message>(
        r#"
        INSERT INTO activity.messages (space_id, session_id, anonymous_id, content, reply_to, poll_options)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, space_id, anonymous_id, content, reply_to, created_at, moderation_status::text
        "#,
    )
    .bind(space_id)
    .bind(payload.session_id)
    .bind(anonymous_id)
    .bind(payload.content)
    .bind(payload.reply_to)
    .bind(options.as_ref().map(|items| serde_json::json!(items)))
    .fetch_one(&state.pool)
    .await?;

    message.reply_content = reply_content;
    if let Some(options) = &options {
        message.poll = Some(
            serde_json::json!({"options": options, "counts": vec![0; options.len()], "selected": null}),
        );
    }

    let _ = state
        .moderation_tx
        .send(ModerationJob {
            message_id: message.id,
            content: format!(
                "{} {}",
                message.content,
                options.unwrap_or_default().join(" ")
            ),
        })
        .await;

    let event = serde_json::json!({
        "type": "message",
        "message": message,
    });
    let _ = state.broadcast_sender(space_id).send(event.to_string());
    Ok(Json(message))
}

#[utoipa::path(post, path = "/messages/{message_id}/vote", request_body = VoteRequest)]
pub async fn vote_poll(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(message_id): Path<Uuid>,
    Json(payload): Json<VoteRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let space_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT space_id FROM activity.messages WHERE id = $1 AND deleted_at IS NULL AND moderation_status <> 'hidden' AND poll_options IS NOT NULL"
    ).bind(message_id).fetch_optional(&state.pool).await?.ok_or(ApiError::NotFound)?;
    active_session_anonymous_id(&state, user_id, space_id, payload.session_id).await?;
    let result = sqlx::query(
        "INSERT INTO activity.poll_votes (message_id, user_id, option_index) SELECT id, $2, $3 FROM activity.messages WHERE id = $1 AND deleted_at IS NULL AND moderation_status <> 'hidden' AND $3 >= 0 AND $3 < jsonb_array_length(poll_options) ON CONFLICT (message_id, user_id) DO UPDATE SET option_index = EXCLUDED.option_index"
    ).bind(message_id).bind(user_id).bind(payload.option_index).execute(&state.pool).await?;
    if result.rows_affected() == 0 {
        return Err(ApiError::Validation("Invalid poll option".into()));
    }
    let event = serde_json::json!({"type": "poll_updated", "message_id": message_id});
    let _ = state.broadcast_sender(space_id).send(event.to_string());
    Ok(Json(event))
}

#[utoipa::path(post, path = "/messages/{message_id}/report", request_body = ReportMessageRequest)]
pub async fn report_message(
    AuthUser { id: reporter_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(message_id): Path<Uuid>,
    Json(payload): Json<ReportMessageRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    payload
        .validate()
        .map_err(|error| ApiError::Validation(error.to_string()))?;
    let (space_id,) = sqlx::query_as::<_, (Uuid,)>(
        "SELECT space_id FROM activity.messages WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(message_id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(ApiError::NotFound)?;

    let has_session = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM activity.sessions WHERE user_id = $1 AND space_id = $2 AND status IN ('active', 'grace') AND expires_at > now())",
    )
    .bind(reporter_id)
    .bind(space_id)
    .fetch_one(&state.pool)
    .await?;
    if !has_session {
        return Err(ApiError::Forbidden);
    }

    let report_id: Uuid = sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO activity.reports (reporter_id, message_id, reason) VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(reporter_id)
    .bind(message_id)
    .bind(payload.reason)
    .fetch_one(&state.pool)
    .await?;
    Ok(Json(
        serde_json::json!({ "id": report_id, "status": "pending" }),
    ))
}

pub async fn delete_message(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(message_id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    let result = sqlx::query(
        r#"
        UPDATE activity.messages m
        SET deleted_at = now(), content = ''
        FROM activity.sessions s
        WHERE m.id = $1
          AND m.session_id = s.id
          AND s.user_id = $2
          AND m.created_at > now() - interval '15 minutes'
          AND m.deleted_at IS NULL
        "#,
    )
    .bind(message_id)
    .bind(user_id)
    .execute(&state.pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(ApiError::Forbidden);
    }
    Ok(Json(serde_json::json!({ "status": "deleted" })))
}

pub async fn react_message(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(message_id): Path<Uuid>,
    Json(payload): Json<ReactRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    payload
        .validate()
        .map_err(|error| ApiError::Validation(error.to_string()))?;
    let emoji = payload.emoji.trim();
    if emoji.is_empty() {
        return Err(ApiError::Validation("emoji is required".to_string()));
    }

    let session_space = sqlx::query_as::<_, (Uuid,)>("SELECT space_id FROM activity.sessions WHERE id = $1 AND user_id = $2 AND status = 'active' AND expires_at > now()")
        .bind(payload.session_id)
        .bind(user_id)
        .fetch_optional(&state.pool)
        .await?
        .ok_or(ApiError::Forbidden)?;
    let message_space = sqlx::query_as::<_, (Uuid,)>(
        "SELECT space_id FROM activity.messages WHERE id = $1 AND deleted_at IS NULL AND moderation_status <> 'hidden'",
    )
    .bind(message_id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(ApiError::NotFound)?;
    let space_id = message_space.0;
    if session_space.0 != space_id {
        return Err(ApiError::Forbidden);
    }

    sqlx::query("INSERT INTO activity.reactions (message_id, session_id, emoji) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING")
        .bind(message_id)
        .bind(payload.session_id)
        .bind(emoji)
        .execute(&state.pool)
        .await?;

    let count: i64 = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM activity.reactions WHERE message_id = $1 AND emoji = $2",
    )
    .bind(message_id)
    .bind(emoji)
    .fetch_one(&state.pool)
    .await?;

    let event = serde_json::json!({
        "type": "reaction",
        "message_id": message_id,
        "emoji": emoji,
        "count": count,
    });
    let _ = state.broadcast_sender(space_id).send(event.to_string());

    Ok(Json(event))
}

async fn websocket(
    ws: WebSocketUpgrade,
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(space_id): Path<Uuid>,
) -> ApiResult<Response> {
    let has_session = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM activity.sessions WHERE user_id = $1 AND space_id = $2 AND status IN ('active', 'grace') AND expires_at > now())",
    )
    .bind(user_id)
    .bind(space_id)
    .fetch_one(&state.pool)
    .await?;
    if !has_session {
        return Err(ApiError::Forbidden);
    }

    Ok(ws.on_upgrade(move |socket| websocket_session(state, socket, space_id)))
}

async fn websocket_session(state: Arc<AppState>, mut socket: WebSocket, space_id: Uuid) {
    let mut rx = state.broadcast_sender(space_id).subscribe();
    loop {
        tokio::select! {
            received = rx.recv() => match received {
                Ok(text) => {
                    if socket.send(WsMessage::Text(text)).await.is_err() {
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            },
            incoming = socket.recv() => match incoming {
                Some(Ok(WsMessage::Close(_))) | None => break,
                Some(Ok(WsMessage::Ping(payload))) => {
                    if socket.send(WsMessage::Pong(payload)).await.is_err() {
                        break;
                    }
                }
                _ => {}
            },
        }
    }
}

async fn active_session_anonymous_id(
    state: &Arc<AppState>,
    user_id: Uuid,
    space_id: Uuid,
    session_id: Uuid,
) -> ApiResult<String> {
    let row = sqlx::query_as::<_, (String,)>(
        "SELECT anonymous_id FROM activity.sessions WHERE id = $1 AND user_id = $2 AND space_id = $3 AND status IN ('active', 'grace') AND expires_at > $4",
    )
    .bind(session_id)
    .bind(user_id)
    .bind(space_id)
    .bind(Utc::now() - Duration::seconds(1))
    .fetch_optional(&state.pool)
    .await?
    .ok_or(ApiError::Forbidden)?;
    Ok(row.0)
}

async fn validate_reply_target(
    state: &Arc<AppState>,
    space_id: Uuid,
    reply_id: Uuid,
) -> ApiResult<String> {
    sqlx::query_scalar::<_, String>(
        "SELECT content FROM activity.messages WHERE id = $1 AND space_id = $2 AND deleted_at IS NULL AND moderation_status <> 'hidden'",
    )
    .bind(reply_id)
    .bind(space_id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(ApiError::NotFound)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn polls_require_distinct_nonempty_bounded_options() {
        for options in [
            vec!["Yes"],
            vec!["Yes", " yes "],
            vec!["Yes", " "],
            vec!["a", "b", "c", "d", "e", "f", "g"],
        ] {
            assert!(validate_poll_options(
                &options.into_iter().map(String::from).collect::<Vec<_>>()
            )
            .is_err());
        }
        assert!(validate_poll_options(&["a".repeat(101), "No".into()]).is_err());
        assert!(validate_poll_options(&["Yes".into(), "No".into()]).is_ok());
    }
}
