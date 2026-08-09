# flutter-frontend.ps1 - run Flutter commands against apps/frontend from the repo root.
#
# Usage (from anywhere, but designed for the repo root):
#   .\flutter-frontend.ps1 run -d chrome
#   .\flutter-frontend.ps1 pub get
#   .\flutter-frontend.ps1 analyze
#
# All arguments are forwarded verbatim to the Flutter tool, which is invoked
# with apps/frontend as the working directory. The caller's current directory
# is restored afterwards.

Push-Location (Join-Path $PSScriptRoot 'apps/frontend')
try {
    & flutter @args
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}
exit $code
