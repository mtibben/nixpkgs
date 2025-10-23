# Reproducing the __pycache__ Bug

## The Bug

The `google-cloud-sdk` package produces non-deterministic builds. On some CI nodes, the build output contains `__pycache__` directories with Python bytecode (`.pyc` files), while on others it doesn't.

Example from CI:
```
/nix/store/6srihrr1wpa7nzq6m8z8g6jw7cirg58z-google-cloud-sdk-537.0.0
└── Contains __pycache__ directories
```

## Root Cause

`PYTHONDONTWRITEBYTECODE=1` is only set in the `installCheckPhase` (line 165 of `package.nix`), but not in the `installPhase` where the installation happens. When Python code executes during installation, it creates bytecode files.

## Reproduction

### Method 1: Side-by-side comparison (Recommended)

This reliably demonstrates the bug and the fix in one build:

```bash
nix-build force-reproduce-bug.nix
nix log result
```

**Expected output:**
```
✗ BUG CONFIRMED!
  Found: 7 __pycache__ dirs, 10 .pyc files

✓ Fix works!
  No bytecode found
```

This builds two versions side-by-side:
- **Buggy version** - without `PYTHONDONTWRITEBYTECODE=1` (reproduces the bug)
- **Fixed version** - with `PYTHONDONTWRITEBYTECODE=1` (shows the fix works)

The test explicitly triggers Python imports to reliably manifest the bug.

### Method 2: Standard reproducibility check

Test if the actual package is reproducible using Nix's built-in check:

```bash
nix-build '<nixpkgs>' -A google-cloud-sdk --check
```

**If the bug exists**, this will fail with:
```
error: derivation '/nix/store/...-google-cloud-sdk-537.0.0.drv' may not be deterministic:
output '/nix/store/...-google-cloud-sdk-537.0.0' differs from previous round
```

**Note**: This may not always fail because the bug is non-deterministic (depends on whether Python imports occur during the build). Method 1 is more reliable.

## Inspection

After running the test, you can inspect the builds:

```bash
# Find the buggy build path from the output, then:
find /nix/store/XXX-google-cloud-sdk-BUGGY-forced -name __pycache__

# Should show multiple __pycache__ directories

# Find the fixed build path from the output, then:
find /nix/store/XXX-google-cloud-sdk-FIXED -name __pycache__

# Should show nothing
```

## The Fix

Add as a derivation attribute in `package.nix` (around line 69, in the `stdenv.mkDerivation` block):

```nix
stdenv.mkDerivation rec {
  pname = "google-cloud-sdk";
  inherit (data) version;

  src = fetchurl (sources stdenv.hostPlatform.system);

  # Prevent Python from writing bytecode to ensure build determinism
  PYTHONDONTWRITEBYTECODE = "1";

  buildInputs = [ python3 ];
  # ... rest of derivation
}
```

This sets the environment variable for **all phases** of the build (unpack, patch, configure, build, install, fixup, installCheck), ensuring Python never creates bytecode at any point.

**Why this approach?**
- ✅ Most robust - applies to all build phases
- ✅ Cleaner than setting in individual phases
- ✅ Standard Nix pattern for environment variables
- ✅ Cannot be missed if phases are overridden
