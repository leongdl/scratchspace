#!/usr/bin/env python3
"""
find_missing_deps.py

Discovers all missing shared library dependencies for an application in a Docker container.
Uses ldd to scan ELF binaries and find missing .so files.

Usage:
    python find_missing_deps.py [--no-build] [--image IMAGE] [--dockerfile DOCKERFILE] [--scan-paths PATHS]
"""

import argparse
import subprocess
import sys
from pathlib import Path
from typing import List


def run_command(cmd: List[str], capture: bool = True, timeout: int = 300) -> subprocess.CompletedProcess:
    """Run a command and return the result."""
    return subprocess.run(
        cmd,
        capture_output=capture,
        text=True,
        timeout=timeout,
    )


def build_docker_image(dockerfile: str, image_name: str, context_dir: Path) -> bool:
    """Build the Docker image."""
    print(f"[1/3] Building Docker image '{image_name}' from {dockerfile}...")
    result = run_command(
        ["docker", "build", "-t", image_name, "-f", dockerfile, "."],
        capture=False,
    )
    if result.returncode != 0:
        print(f"ERROR: Failed to build image", file=sys.stderr)
        return False
    print(f"      Image built: {image_name}")
    return True


def scan_for_missing_libs(image_name: str, scan_paths: List[str]) -> List[str]:
    """Scan ELF files in the container for missing libraries."""
    # Build the scan command for inside the container
    scan_commands = []
    for path in scan_paths:
        # Scan direct files (*.bin, *.so, *.so.*)
        scan_commands.append(f'for f in {path}/*.bin {path}/*.so {path}/*.so.*; do [ -f "$f" ] && ldd "$f" 2>/dev/null; done')
        # Scan subdirectories for plugins
        scan_commands.append(f'for dir in {path}/platforms {path}/plugins {path}/imageformats {path}/iconengines; do '
                           f'if [ -d "$dir" ]; then for f in "$dir"/*.so "$dir"/*.so.*; do [ -f "$f" ] && ldd "$f" 2>/dev/null; done; fi; done')
    
    full_command = " && ".join(scan_commands)
    
    result = run_command([
        "docker", "run", "--rm", image_name,
        "sh", "-c", full_command
    ])
    
    if result.returncode != 0 and not result.stdout:
        print(f"WARNING: Scan returned non-zero exit code", file=sys.stderr)
    
    # Parse ldd output for "not found" entries
    missing_libs: set[str] = set()
    for line in result.stdout.splitlines():
        if "not found" in line:
            # Format: "libfoo.so.1 => not found"
            lib_name = line.strip().split()[0]
            missing_libs.add(lib_name)
    
    return sorted(missing_libs)


def filter_bundled_libs(libs: List[str], exclude_patterns: List[str]) -> List[str]:
    """Filter out libraries that are bundled with the application."""
    filtered = []
    for lib in libs:
        exclude = False
        for pattern in exclude_patterns:
            if lib.startswith(pattern):
                exclude = True
                break
        if not exclude:
            filtered.append(lib)
    return filtered


def main() -> int:
    parser = argparse.ArgumentParser(description="Find missing shared library dependencies in a Docker container")
    parser.add_argument("--no-build", action="store_true", help="Skip Docker build, assume image exists")
    parser.add_argument("--image", default="vray-minimal", help="Docker image name (default: vray-minimal)")
    parser.add_argument("--dockerfile", default="Dockerfile.reverse-engineer", help="Dockerfile to build")
    parser.add_argument("--scan-paths", default="/opt/vray/bin,/opt/vray/lib", help="Comma-separated paths to scan")
    parser.add_argument("--output", default="missing-libs.txt", help="Output file for missing libraries")
    parser.add_argument("--exclude", default="libvray,libchaos,libscatter,libtexcompress,libvfb,libVRay,libQt5,libcuda,librt_cuda",
                       help="Comma-separated prefixes to exclude (bundled libs)")
    args = parser.parse_args()

    script_dir = Path(__file__).parent
    scan_paths = [p.strip() for p in args.scan_paths.split(",")]
    exclude_patterns = [p.strip() for p in args.exclude.split(",")]

    print("=== Dependency Discovery (Python) ===")
    print()

    # Step 1: Build image if needed
    if not args.no_build:
        if not build_docker_image(args.dockerfile, args.image, script_dir):
            return 1
    else:
        print("[1/3] Skipping build (--no-build specified)")
    print()

    # Step 2: Scan for missing libraries
    print("[2/3] Scanning for missing dependencies inside container...")
    missing_libs = scan_for_missing_libs(args.image, scan_paths)
    
    # Filter out bundled libraries
    missing_libs = filter_bundled_libs(missing_libs, exclude_patterns)
    
    print(f"      Found {len(missing_libs)} missing libraries")
    print()

    # Step 3: Save results
    output_path = script_dir / args.output
    output_path.write_text("\n".join(missing_libs) + "\n" if missing_libs else "")
    
    print(f"[3/3] Results saved to: {args.output}")
    print()
    print("=== Missing Libraries ===")
    if missing_libs:
        for lib in missing_libs:
            print(f"  {lib}")
    else:
        print("  (none found - all dependencies satisfied)")
    print()
    print("=== Next Steps ===")
    print("Run: python resolve_deps.py --dry-run")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
