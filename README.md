# Export and Go

Fire-and-forget MariaDB backup to RustFS. Run one command, then get back to your work.

    ./export-and-send.sh wordpress_staging

The command returns immediately. In the background, the script:

1. Installs age and awscli if they are missing
2. Exports the database
3. Encrypts the dump with age
4. Uploads it to RustFS
5. Cleans up the temp files, the downloaded CA certificate and `.env`

No password prompts, no waiting on the terminal, and no need to keep the session open.
Check the result any time with `tail -f export-and-send.log`.

## Files

| File | Purpose |
|---|---|
| export-and-send.sh | The script: check and install tools, export, encrypt, upload, remove `.env` |
| .env | RustFS, CA URL and age settings, deleted after a successful run |
| .env.example | Template to restore `.env` before the next run |

## Requirements

- Passwordless sudo for the user, or run it as root (the script uses `sudo -n`, so it fails instead of waiting for a password)
- mariadb-dump (MariaDB client), already present on a DB host
- The server trusts the certificate of `vaultx.internal.ebc.edu.kh`
- Internet access to `awscli.amazonaws.com` and the apt mirrors on the first run, only if age or awscli is missing

## Setup

    git clone https://github.com/Kheav-Kienghok/Export-and-Go-Fire-and-Forget-MariaDB-Backup-to-RustFS.git && cd Export-and-Go-Fire-and-Forget-MariaDB-Backup-to-RustFS
    cp .env.example .env
    vi .env

Set `RUSTFS_ACCESS_KEY` and `RUSTFS_SECRET_KEY`. `AGE_RECIPIENT` is the age public key.

## Run

    sudo ./export-and-send.sh wordpress_staging

It returns immediately and keeps running in the background.

    tail -f export-and-send.log

Result: `s3://database/wordpress_staging_YYYYMMDD_HHMMSS.sql.age`

On the first run the log also shows `installing age` and `installing awscli` if they were missing.

## Next run

`.env` is removed after a successful upload. Restore it first:

    cp .env.example .env
    vi .env

If anything fails, `.env` is kept so you can retry.

## Restore a backup

    aws --endpoint-url https://s3.internal.example.com s3 cp s3://database/FILE.sql.age .
    age -d -i identity.txt FILE.sql.age | mariadb TARGET_DB

## Notes

- Keep the age private identity off this host, or the backups can't be decrypted.
- `.env.example` has no real keys. Keep the access keys in Vault, not in the zip.
- Use a RustFS access key limited to writing the `database` bucket.
