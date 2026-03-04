# Docker RCA Template

**Тип ошибки:** Docker (container, image, volume, network)

## Layer Analysis (Bottom-Up)

```
┌─────────────────────────────────────────┐
│  Layer 5: RUNTIME (container process)   │ ← Ошибка проявляется здесь
├─────────────────────────────────────────┤
│  Layer 4: NETWORK (connectivity)        │ ← DNS, ports, routing
├─────────────────────────────────────────┤
│  Layer 3: VOLUME (persistent data)      │ ← Mounts, permissions
├─────────────────────────────────────────┤
│  Layer 2: IMAGE (build config)          │ ← Dockerfile, layers
├─────────────────────────────────────────┤
│  Layer 1: HOST (docker daemon)          │ ← Base infrastructure
└─────────────────────────────────────────┘
```

## 5 Whys for Docker

### Layer 5: Runtime
1. **Почему контейнер упал/недоступен?**
   - [ ] Process exited with code X
   - [ ] OOM killed
   - [ ] Health check failed
   - [ ] Application error

### Layer 4: Network
2. **Почему нет connectivity?**
   - [ ] Wrong network assignment
   - [ ] DNS resolution failure
   - [ ] Port not exposed/mapped
   - [ ] Firewall blocking

### Layer 3: Volume
3. **Почему данные/доступ отсутствуют?**
   - [ ] Volume not mounted
   - [ ] Permission denied
   - [ ] Path mismatch
   - [ ] Bind mount issue

### Layer 2: Image
4. **Почему image некорректен?**
   - [ ] Missing dependencies
   - [ ] Wrong base image
   - [ ] Build cache issue
   - [ ] Multi-stage copy error

### Layer 5: Host
5. **Почему daemon/config проблемен?**
   - [ ] Docker daemon not running
   - [ ] Disk space exhausted
   - [ ] Resource limits hit
   - [ ] Config file error

## Docker-Specific Checks

```bash
# Container status
docker ps -a --filter "name=<container>"
docker logs <container> --tail 100

# Network inspection
docker network inspect <network>
docker inspect <container> --format '{{json .NetworkSettings.Networks}}'

# Volume inspection
docker volume ls
docker inspect <container> --format '{{json .Mounts}}'

# Image layers
docker image history <image>
docker image inspect <image>

# Resource usage
docker stats --no-stream
docker system df
```

## Common Root Causes

| Symptom | Likely Root Cause |
|---------|-------------------|
| 404/502 | Wrong network, missing traefik labels |
| OOM | Memory limit too low, memory leak |
| Permission denied | Volume permissions, user mismatch |
| Image pull error | Registry auth, rate limit, tag missing |
| DNS failure | Network isolation, /etc/hosts, DNS config |

## Docker RCA Example

```
❌ ОШИБКА: 404 при обращении к moltis.ainetic.tech

📝 Layer 5: Почему 404?
   → Traefik не находит маршрут к контейнеру

📝 Layer 4: Почему нет маршрута?
   → Контейнер в сети traefik_proxy, а Traefik в traefik-net

📝 Layer 3: (не применимо)

📝 Layer 2: Почему сеть неправильная?
   → В docker-compose.yml указана traefik_proxy

📝 Layer 1: Почему конфиг не совпадает с продакшеном?
   → Нет валидации сетей перед деплоем

🎯 КОРНЕВАЯ ПРИЧИНА: Отсутствие preflight-check для Docker сетей
```

---
*Шаблон для Docker-specific RCA анализа*
