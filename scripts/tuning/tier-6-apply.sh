#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 6: Memory allocator (compile-time optimization)."
echo ""
echo "This tier is a compile-time change, not a runtime sysctl."
echo "The server binary should be compiled with jemalloc for optimal"
echo "performance under high connection counts."
echo ""

if grep -q "jemallocator" /root/scalable-websockets/server/Cargo.toml 2>/dev/null; then
  echo "  jemallocator is already present in server/Cargo.toml."
else
  echo "  To enable jemalloc, add to server/Cargo.toml:"
  echo "    [dependencies]"
  echo '    tikv-jemallocator = "0.6"'
  echo ""
  echo "  And add to server/src/main.rs:"
  echo '    #[global_allocator]'
  echo '    static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;'
  echo ""
  echo "  Then rebuild: cargo build --release -p server"
fi

echo ""
echo "Tier 6: No runtime changes applied. Rebuild the binary if needed."
