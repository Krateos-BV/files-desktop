# nextcloud-desktop — Claude Code Project Context

## Concurrent-ticket isolation (git worktrees)

`/root/projects/nextcloud-desktop` is the permanent main checkout, used for single-ticket
sessions as-is — no change needed there.

If a second XNT/INF ticket needs to touch this repo while another ticket is still mid-work
here, do NOT reuse this checkout directly (uncommitted changes from the two tickets can get
swept into the same commit). Instead, from inside this clone, create a throwaway worktree:

```
git worktree add ../nextcloud-desktop-<TICKET-KEY> <branch-name>
```

Work the second ticket entirely inside `../nextcloud-desktop-<TICKET-KEY>`. Once that ticket
is merged/closed, remove the worktree:

```
git worktree remove ../nextcloud-desktop-<TICKET-KEY>
```

Run `git worktree list` from either location to see all active worktrees for this repo.
