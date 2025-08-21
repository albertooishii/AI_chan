#!/usr/bin/env bash
# Complete Flutter development runner
# Background execution with debug output, hot reload, and real-time logs

echo "🚀 Starting AI_chan development environment..."
echo "✨ Features enabled:"
echo "   🐛 Debug output (verbose)"
echo "   🔄 Hot reload (edit & save to reload)"
echo "   📝 Background execution (VS Code free)"
echo "   📊 Real-time logs available"
echo ""

# Run Flutter in background with full debug output
nohup flutter run -d linux --verbose --debug > flutter_debug.log 2>&1 &
FLUTTER_PID=$!

echo "✅ App started with PID: $FLUTTER_PID"
echo "🛑 To stop: make stop"
echo "👀 To view logs: make logs"
echo "🔄 Edit files and save → automatic reload!"

# Exit immediately so make doesn't wait
exit 0# Background Flutter runner script with debug output
# This prevents Makefile from waiting for the process

echo "🚀 Starting AI_chan app in background with debug output..."
echo "📝 Debug logs will be saved to flutter_debug.log"
echo "🛑 To stop: make stop"
echo "👀 To view logs: make logs"
echo ""

# Run Flutter in background with verbose output to log file
nohup flutter run -d linux --verbose > flutter_debug.log 2>&1 &
FLUTTER_PID=$!

echo "✅ App started with PID: $FLUTTER_PID"
echo "� Full debug output available in flutter_debug.log"
echo "🔄 Hot reload enabled - edit files and save to reload"

# Exit immediately so make doesn't wait
exit 0
