# Fix lockfile detection for package managers

# New behavior: Lockfiles are collected per directory level without accumulation across parent directories.
# Package manager selection now uses a priority order: pnpm > bun > yarn > npm.

# Replace the root/manager detection loop accordingly.
# Ensure locks_found reflects only the chosen root level's lockfiles.

lockfiles_found = []
manager_priority = ['pnpm', 'bun', 'yarn', 'npm']

def detect_lockfiles(directory):
    for manager in manager_priority:
        if f'{manager}-lock.yaml' in os.listdir(directory):
            locks_found = [f for f in os.listdir(directory) if f.endswith(f'{manager}-lock.yaml')]
            lockfiles_found.extend(locks_found)
            break  # Stop after the first manager found
    return lockfiles_found
