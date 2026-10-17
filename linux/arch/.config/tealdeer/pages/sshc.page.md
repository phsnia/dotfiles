# SSH Cheat Sheet

## Connecting

```bash
ssh user@host                  # Connect to remote host
ssh -p 2222 user@host          # Connect on specific port
ssh -i key.pem user@host       # Use specific key
```

## Tunneling

```bash
ssh -L 8080:localhost:80 user@host   # Local port forward
ssh -R 8080:localhost:80 user@host   # Remote port forward
ssh -D 1080 user@host                # SOCKS proxy
```

## Key Management

```bash
ssh-keygen -t ed25519          # Generate key pair
ssh-copy-id user@host          # Copy key to remote
ssh-add ~/.ssh/id_ed25519      # Add key to agent
ssh-add -l                     # List loaded keys
ssh-keygen -p -f key.pem       # Change key passphrase
ssh-keygen -y -f key.pem       # Extract public key
```

## File Transfer (scp)

```bash
scp file user@host:/path/      # Copy file to remote
scp user@host:/path/file .     # Copy file from remote
scp -r dir user@host:/path/    # Copy directory recursively
scp -P 2222 file user@host:/   # Use specific port
```
