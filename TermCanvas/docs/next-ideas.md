# TermCanvas: Next Ideas

## Best Next Additions

### 1. Autosave + reopen last canvas
- Persist the full canvas state locally.
- Restore the last-opened workspace automatically on launch.
- This turns the app from a demo into a real tool.

### 2. Frames / groups
- Let users draw named containers around related terminals and text.
- Good examples: `backend`, `infra`, `deploy`, `logs`, `prod`.
- This makes larger canvases readable very quickly.

### 3. Broadcast input to selected terminals
- Select multiple terminals and send the same input to all of them.
- Useful for multi-service workflows, repeated setup, and debugging clusters.
- This is one of the most powerful workflow upgrades.

### 4. Minimap
- Add a small overview of the infinite canvas in one corner.
- Helps navigation once the canvas gets large.

### 5. Terminal layout templates
- Save and respawn common setups in one click.
- Examples: frontend stack, k8s debugging, deploy board, prod monitoring.

### 6. Connectors / arrows
- Let users show relationships between terminals, notes, and groups.
- Useful for documenting flows and operator sequences.

### 7. Command blocks
- Text blocks that can also store runnable shell snippets.
- Click or shortcut to send them into a selected terminal.
- This could become a signature feature for the app.

### 8. Freeze terminal to snapshot
- Convert a live terminal into a static captured output card.
- Good for saving evidence, notes, and presentations.

## Suggested Build Order

### Immediate
1. Autosave + reopen last canvas
2. Frames / groups
3. Broadcast input to selected terminals

### Later
4. Minimap
5. Templates
6. Connectors
7. Command blocks
8. Terminal snapshots

## Things To Avoid For Now
- Tabs inside terminals
- Heavy window chrome
- Theme work before workflow depth
- Collaboration or sync before local persistence is solid

