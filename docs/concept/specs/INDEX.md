# Speckit Feature Specs

**Version**: 1.0.0  
**Date created**: 2026-03-17  
**Date updated**: 2026-03-17  
**Status**: Active

---

## Purpose

Этот раздел хранит feature-level артефакты Speckit, которые служат входом для последовательных команд `command-speckit-plan` и `command-speckit-tasks`.

---

## Active Features

### [001-approval-level-user-story-bpmn](./001-approval-level-user-story-bpmn/spec.md)

- **Spec**: [spec.md](./001-approval-level-user-story-bpmn/spec.md)
- **BPMN 2.0**: [factory-e2e.bpmn](./001-approval-level-user-story-bpmn/factory-e2e.bpmn)
- **Approval Zoom-In**: [approval-level.bpmn](./001-approval-level-user-story-bpmn/approval-level.bpmn)
- **Checklist**: [checklists/requirements.md](./001-approval-level-user-story-bpmn/checklists/requirements.md)
- **Intent**: каноническое описание полного end-to-end маршрута фабрики плюс детализированный approval contour как входа для следующей фазы Speckit planning и task decomposition.

---

## Usage

1. Начать со [spec.md](./001-approval-level-user-story-bpmn/spec.md).
2. Проверить процессную модель в [factory-e2e.bpmn](./001-approval-level-user-story-bpmn/factory-e2e.bpmn).
3. Уточнить согласовательный контур в [approval-level.bpmn](./001-approval-level-user-story-bpmn/approval-level.bpmn).
4. Подтвердить readiness через [requirements checklist](./001-approval-level-user-story-bpmn/checklists/requirements.md).
5. Переходить к `command-speckit-plan`.
