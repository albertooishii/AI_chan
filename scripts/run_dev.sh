#!/usr/bin/env bash
# Complete Flutter development runner
# Everything you want: logs + colors + hot reload + interactive + non-blocking

echo "🚀 Starting AI_chan development environment..."
echo "✨ Features enabled:"
echo "   🐛 Debug mode with colors"
echo "   🔄 Hot reload (press 'r')" 
echo "   📝 Real-time logs with colors"
echo "   🖥️ Interactive commands"
echo "   🎯 Non-blocking VS Code"
echo ""

# The secret: use 'script' command to create pseudo-terminal
# This gives us colors + interactivity but doesn't block VS Code
script -qf -c "flutter run -d linux --debug" /dev/null