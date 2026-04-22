#!/usr/bin/env bash
set -euo pipefail

sudo ddcutil -b 5 setvcp 0x60 0x0f
