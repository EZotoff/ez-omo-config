# OhMyOpenCode Skills

This directory contains specialized skill modules that extend the OpenCode agent capabilities for specific domains and workflows.

## Skills Overview

### wisdom/
Wisdom propagation system for accumulating cross-plan learnings. Records patterns, conventions, and successful approaches discovered during plan execution. Enables knowledge reuse across development sessions.
- **Dependencies**: None
- **Use Case**: Searching and recording learnings from plan execution

### atlas-review-handler/
Atlas-level review orchestration handler. Processes automated review results from sub-agents, triages findings, delegates critical fixes, and manages the complete review workflow (request → delegate → receive results → parse findings → fix loop → verify).
- **Dependencies**: review-protocol
- **Use Case**: Managing review workflows and handling code review automation

### review-protocol/
Automated code review agent that analyzes git diffs and returns structured findings. Verifies code quality, catches issues, and provides structured feedback in CRITICAL/WARNING/INFO format.
- **Dependencies**: None
- **Use Case**: Conducting code reviews of uncommitted or recent changes

### playwright/
Browser testing agent using playwright-cli. Verifies frontend functionality works correctly with actual user-visible behavior testing, not just error checking.
- **Dependencies**: None
- **Use Case**: Testing UI functionality, exploratory testing, verifying app works correctly

### deployment/
Infrastructure and deployment helper for setting up servers, configuring ports, running services locally, docker-compose, and deployment-related tasks. Maintains port registry to avoid conflicts.
- **Dependencies**: None
- **Use Case**: Managing server setup, Docker deployments, port configuration

### frontend-ui-ux/
Designer-turned-developer UI/UX specialist that crafts stunning UI/UX with multi-dimensional analysis for deep design work. Provides UI/UX expertise even without design mockups.
- **Dependencies**: None
- **Use Case**: Visual engineering, UI design improvements, UX enhancements
