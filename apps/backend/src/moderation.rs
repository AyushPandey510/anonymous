use sqlx::PgPool;
use uuid::Uuid;

#[derive(Debug)]
pub struct ModerationJob {
    pub message_id: Uuid,
    pub content: String,
}

#[derive(Debug, PartialEq, Eq)]
enum ModerationDecision {
    Clean,
    SoftFlag(&'static str),
    HardBlock(&'static str),
}

pub async fn worker(pool: PgPool, mut rx: tokio::sync::mpsc::Receiver<ModerationJob>) {
    while let Some(job) = rx.recv().await {
        if let Err(error) = moderate_one(&pool, job).await {
            tracing::warn!(%error, "moderation job failed");
        }
    }
}

async fn moderate_one(pool: &PgPool, job: ModerationJob) -> anyhow::Result<()> {
    match classify(&job.content) {
        ModerationDecision::Clean => {}
        ModerationDecision::SoftFlag(category) => {
            sqlx::query("UPDATE activity.messages SET moderation_status = 'flagged' WHERE id = $1")
                .bind(job.message_id)
                .execute(pool)
                .await?;
            insert_event(pool, job.message_id, category, "soft").await?;
        }
        ModerationDecision::HardBlock(category) => {
            sqlx::query("UPDATE activity.messages SET moderation_status = 'hidden' WHERE id = $1")
                .bind(job.message_id)
                .execute(pool)
                .await?;
            insert_event(pool, job.message_id, category, "hard").await?;
        }
    }
    Ok(())
}

async fn insert_event(
    pool: &PgPool,
    message_id: Uuid,
    category: &str,
    severity: &str,
) -> anyhow::Result<()> {
    sqlx::query("INSERT INTO activity.moderation_events (message_id, category, severity) VALUES ($1, $2, $3)")
        .bind(message_id)
        .bind(category)
        .bind(severity)
        .execute(pool)
        .await?;
    Ok(())
}

fn classify(content: &str) -> ModerationDecision {
    let lowered = content.to_lowercase();
    if ["kill myself", "self harm", "bomb threat", "shoot up"]
        .iter()
        .any(|needle| lowered.contains(needle))
    {
        return ModerationDecision::HardBlock("severe_safety");
    }
    if ["idiot", "stupid", "harass"]
        .iter()
        .any(|needle| lowered.contains(needle))
    {
        return ModerationDecision::SoftFlag("toxicity");
    }
    ModerationDecision::Clean
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hard_blocks_severe_content() {
        assert_eq!(
            classify("this is a bomb threat"),
            ModerationDecision::HardBlock("severe_safety")
        );
    }

    #[test]
    fn soft_flags_toxicity() {
        assert_eq!(
            classify("that was stupid"),
            ModerationDecision::SoftFlag("toxicity")
        );
    }
}
