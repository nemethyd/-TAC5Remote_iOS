# TestFlight Setup

## Local files already prepared

- `secrets/Issuer_ID.txt`
- `secrets/Key_ID.txt`
- `secrets/AuthKey_U4739W5L27.p8`

## GitHub repository secrets to create

Go to GitHub repository settings, then `Secrets and variables` -> `Actions`, and create:

1. `APP_STORE_CONNECT_ISSUER_ID`
   - paste the contents of `secrets/Issuer_ID.txt`
2. `APP_STORE_CONNECT_KEY_ID`
   - paste the contents of `secrets/Key_ID.txt`
3. `APP_STORE_CONNECT_API_KEY_P8`
   - paste the complete contents of `secrets/AuthKey_U4739W5L27.p8`

## Workflow to run

After the secrets are added, run:

- `.github/workflows/testflight-upload.yml`

from the GitHub Actions `Run workflow` button.

## Notes

- The workflow uses App Store Connect API key authentication.
- The app bundle identifier is `hu.moderato.tac5remote.ios`.
- The Apple Team ID is `8Q774J3K2P`.
- The first TestFlight upload may surface signing or metadata issues that are only visible during archive/export.
