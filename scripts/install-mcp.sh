#!/bin/sh
# Builds the MCP server and registers it in Claude Code (user scope) as "litto".
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product litto-mcp
bin="$(swift build -c release --show-bin-path)/litto-mcp"
claude mcp remove --scope user litto >/dev/null 2>&1 || true
claude mcp add --scope user litto -- "$bin"
echo "Registered litto -> $bin"
