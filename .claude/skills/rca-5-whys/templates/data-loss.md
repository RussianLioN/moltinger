# Data Loss RCA Template

**Тип ошибки:** Data Loss (deleted, corrupted, backup)

## ⚠️ CRITICAL PROTOCOL

```
┌─────────────────────────────────────────────────────┐
│  STOP! DO NOT ATTEMPT RECOVERY WITHOUT ANALYSIS     │
│                                                      │
│  1. STOP     - Halt all operations immediately      │
│  2. SNAPSHOT - Capture current state                │
│  3. ASSESS   - Determine scope of loss              │
│  4. RESTORE  - Only after assessment                │
│  5. ANALYZE  - Find root cause AFTER recovery       │
└─────────────────────────────────────────────────────┘
```

## Data Loss Analysis Framework

```
┌─────────────────────────────────────────┐
│  LAYER 5: DATA (what was affected)      │ ← Files, DB records, volumes
├─────────────────────────────────────────┤
│  LAYER 4: BACKUP (recovery options)     │ ← Last backup, integrity
├─────────────────────────────────────────┤
│  LAYER 3: PROCESS (what caused loss)    │ ← Script, command, migration
├─────────────────────────────────────────┤
│  LAYER 2: SAFEGUARD (what failed)       │ ← Backup, confirmation, dry-run
├─────────────────────────────────────────┤
│  LAYER 1: SYSTEMIC (process gap)        │ ← Missing policy, training
└─────────────────────────────────────────┘
```

## 5 Whys for Data Loss

### Data Layer
1. **Какие данные потеряны/повреждены?**
   - [ ] Files deleted
   - [ ] Database records
   - [ ] Docker volumes
   - [ ] Configuration files
   - [ ] Corrupted data

### Backup Layer
2. **Почему нельзя восстановить из backup?**
   - [ ] No backup exists
   - [ ] Backup too old
   - [ ] Backup corrupted
   - [ ] Backup incomplete
   - [ ] Restore not tested

### Process Layer
3. **Какое действие вызвало потерю?**
   - [ ] rm -rf command
   - [ ] DROP TABLE / TRUNCATE
   - [ ] docker volume rm
   - [ ] Migration script
   - [ ] Sync/overwrite operation

### Safeguard Layer
4. **Почему защита не сработала?**
   - [ ] No confirmation prompt
   - [ ] No dry-run option
   - [ ] Wrong directory context
   - [ ] Force flag used
   - [ ] Backup was disabled

### Systemic Layer
5. **Почему процесс уязвим?**
   - [ ] No data classification
   - [ ] No backup policy
   - [ ] No destructive command review
   - [ ] No staging environment test
   - [ ] Insufficient training

## Data Loss Investigation Commands

```bash
# ⚠️ READ-ONLY - DO NOT MODIFY ANYTHING

# Check what was deleted (if recent)
ls -la . # current directory state
git status # version controlled files
git reflog # recent git operations

# Check backup status
ls -la /backups/ 2>/dev/null || echo "No /backups directory"
docker volume ls | grep backup

# Check disk for recovery potential
df -h .
lsof +L1 # deleted files still open

# Check recent destructive commands
history | grep -E "(rm|DROP|TRUNCATE|DELETE|docker.*rm)"
```

## Recovery Decision Matrix

| Backup Age | Data Criticality | Recovery Action |
|------------|------------------|-----------------|
| < 1 hour | Critical | Restore from backup immediately |
| < 24 hours | High | Restore + manual reconciliation |
| > 24 hours | Medium | Assess manual recreation vs data loss |
| No backup | Any | Professional data recovery services |

## Data Loss RCA Example

```
❌ ОШИБКА: Production database table dropped during migration

📝 STOP: Halt all migrations, preserve logs
📝 SNAPSHOT: Database state, migration logs

📝 Layer 5: Какая таблица?
   → users_preferences (5,000 records)

📝 Layer 4: Backup status?
   → Last backup: 6 hours ago (acceptable loss window)

📝 Layer 3: Какое действие?
   → migration.js executed DROP TABLE instead of ALTER

📝 Layer 4: Почему защита не сработала?
   → No dry-run mode in migration script
   → No review required for production migrations

📝 Layer 5: Почему процесс уязвим?
   → Missing migration review policy
   → No staging environment validation

🎯 КОРНЕВАЯ ПРИЧИНА:
   Absence of migration review policy and mandatory staging validation

📋 IMMEDIATE ACTIONS:
   1. Restore from backup (6h old)
   2. Manual reconciliation of 6h gap
   3. Add migration review requirement
   4. Mandate staging test before production
```

## Prevention Checklist

- [ ] All destructive commands require confirmation
- [ ] Critical data has automated backups
- [ ] Backups are tested regularly
- [ ] Destructive operations have dry-run mode
- [ ] Production changes require review
- [ ] Staging environment exists for testing

---
*Шаблон для Data Loss RCA анализа - КРИТИЧЕСКИЙ ПРИОРИТЕТ*
