#!/usr/bin/env python3
"""
resolve_deps.py

Maps missing shared libraries to RPM packages using dnf provides.
Runs dnf inside a Docker container for accurate Rocky Linux results.

Usage:
    python resolve_deps.py [--dry-run] [--dockerfile] [--image IMAGE]
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional


def run_command(
    cmd: list,
    input_text: Optional[str] = None,
    timeout: int = 300
) -> subprocess.CompletedProcess:
    """Run a command and return the result."""
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        input=input_text,
        timeout=timeout,
    )


def resolve_lib_to_package(image_name: str, lib_name: str) -> Optional[str]:
    """Use dnf provides inside container to find package for a library."""
    result = run_command([
        "docker", "run", "--rm", image_name,
        "dnf", "provides", "-q", f"*/{lib_name}"
    ])
    
    if result.returncode != 0 or not result.stdout.strip():
        return None
    
    # Parse first matching line: "package-version.arch : description"
    for line in result.stdout.splitlines():
        if ":" in line and not line.startswith(" "):
            pkg_full = line.split(":")[0].strip()
            # Remove epoch, version-release, and architecture
            # e.g., "1:libX11-1.7.0-9.el9.x86_64" -> "libX11"
            pkg_name = re.sub(r"^[0-9]+:", "", pkg_full)  # Remove epoch
            pkg_name = re.sub(r"\.(x86_64|i686|noarch)$", "", pkg_name)  # Remove arch
            pkg_name = re.sub(r"-[0-9]+[.:][0-9].*$", "", pkg_name)  # Remove version-release
            # Handle edge case: trailing -1 from epoch removal in package name
            pkg_name = re.sub(r"-[0-9]+$", "", pkg_name) if pkg_name.endswith("-1") else pkg_name
            return pkg_name
    
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Resolve missing libraries to RPM packages")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be installed")
    parser.add_argument("--dockerfile", action="store_true", help="Output dnf install command for Dockerfile")
    parser.add_argument("--image", default="vray-minimal", help="Docker image name (default: vray-minimal)")
    parser.add_argument("--input", default="missing-libs.txt", help="Input file with missing libraries")
    parser.add_argument("--output", default="required-packages.txt", help="Output file for package list")
    args = parser.parse_args()

    script_dir = Path(__file__).parent
    input_path = script_dir / args.input
    output_path = script_dir / args.output

    print("=== Dependency Resolver (Python) ===")
    print()

    # Check input file
    if not input_path.exists():
        print(f"ERROR: {args.input} not found.", file=sys.stderr)
        print("Run find_missing_deps.py first.", file=sys.stderr)
        return 1

    missing_libs = [line.strip() for line in input_path.read_text().splitlines() if line.strip()]
    
    if not missing_libs:
        print(f"No missing libraries found in {args.input}")
        print("All dependencies appear to be satisfied.")
        return 0

    print(f"[1/3] Reading missing libraries from: {args.input}")
    print(f"      Found {len(missing_libs)} libraries to resolve")
    print()

    # Resolve libraries to packages
    print("[2/3] Resolving libraries to packages (inside container)...")
    print()

    packages: set[str] = set()
    not_found: list[str] = []

    for lib in missing_libs:
        print(f"  {lib:<30} -> ", end="", flush=True)
        pkg = resolve_lib_to_package(args.image, lib)
        if pkg:
            print(pkg)
            packages.add(pkg)
        else:
            print("(not found in repos)")
            not_found.append(lib)

    print()

    # Save results
    sorted_packages = sorted(packages)
    output_path.write_text("\n".join(sorted_packages) + "\n" if sorted_packages else "")

    print("[3/3] Summary")
    print()
    print(f"Unique packages needed: {len(sorted_packages)}")
    print()

    if not_found:
        print("WARNING: The following libraries were not found in repos:")
        for lib in not_found:
            print(f"  - {lib}")
        print()
        print("These may need EPEL or manual resolution.")
        print()

    print("=== Packages to Install ===")
    if sorted_packages:
        for pkg in sorted_packages:
            print(f"  {pkg}")
    else:
        print("  (none)")
    print()

    print(f"Package list saved to: {args.output}")
    print()

    # Output based on mode
    pkg_line = " ".join(sorted_packages)
    
    if args.dockerfile:
        print("=== Dockerfile Command ===")
        print(f"RUN dnf install -y {pkg_line}")
        print()
    elif args.dry_run:
        print("=== Dry Run Mode ===")
        print(f"Would run: dnf install -y {pkg_line}")
        print()
        print("To generate Dockerfile command: python resolve_deps.py --dockerfile")
    else:
        print("=== Install Mode ===")
        print("To install in a container, run:")
        print(f"  docker exec <container> dnf install -y {pkg_line}")
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
