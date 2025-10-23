# Force reproduction of the __pycache__ bug
# This modifies google-cloud-sdk to explicitly trigger Python imports during build
# to reliably demonstrate the bug

{ pkgs ? import <nixpkgs> { } }:

let
  # Version that FORCES Python to run and create bytecode
  buggyForced = pkgs.google-cloud-sdk.overrideAttrs (old: {
    name = "google-cloud-sdk-BUGGY-forced";
    
    installPhase = old.installPhase + ''
      echo ""
      echo "========================================"
      echo "FORCING PYTHON IMPORTS TO TRIGGER BUG"
      echo "========================================"
      echo ""
      
      # Force Python to import modules from the installed package
      # This WILL create __pycache__ if PYTHONDONTWRITEBYTECODE is not set
      cd $out/google-cloud-sdk/lib
      
      # Try to import googlecloudsdk modules
      export PYTHONPATH=$out/google-cloud-sdk/lib:$PYTHONPATH
      
      echo "Attempting to import googlecloudsdk modules..."
      python3 -c "import sys; print('Python version:', sys.version)" || true
      
      # This should create __pycache__ directories
      python3 -c "import googlecloudsdk" 2>/dev/null || echo "  (import failed, but may have created bytecode)"
      python3 -c "import googlecloudsdk.core" 2>/dev/null || echo "  (core import failed, but may have created bytecode)"
      python3 -c "import googlecloudsdk.calliope" 2>/dev/null || echo "  (calliope import failed, but may have created bytecode)"
      
      # Also try gslib which is part of gsutil
      cd $out/google-cloud-sdk/platform/gsutil || true
      python3 -c "import gslib" 2>/dev/null || echo "  (gslib import failed, but may have created bytecode)"
      
      echo ""
      echo "Checking for __pycache__ after forced imports..."
      PYCACHE_COUNT=$(find $out -type d -name __pycache__ | wc -l | tr -d ' ')
      PYC_COUNT=$(find $out -type f -name "*.pyc" | wc -l | tr -d ' ')
      
      echo "Found $PYCACHE_COUNT __pycache__ directories"
      echo "Found $PYC_COUNT .pyc files"
      
      if [ "$PYCACHE_COUNT" -gt 0 ] || [ "$PYC_COUNT" -gt 0 ]; then
        echo ""
        echo "✗ BUG REPRODUCED!"
        echo ""
        echo "Sample __pycache__ directories:"
        find $out -type d -name __pycache__ | head -10
        echo ""
      else
        echo ""
        echo "⚠ Bug did not manifest even with forced imports"
        echo "This could mean:"
        echo "  - Imports are failing before bytecode creation"
        echo "  - Python is configured differently"
        echo "  - PYTHONDONTWRITEBYTECODE is set globally"
        echo ""
        echo "Checking if PYTHONDONTWRITEBYTECODE is set:"
        python3 -c "import os; print('PYTHONDONTWRITEBYTECODE =', os.environ.get('PYTHONDONTWRITEBYTECODE', 'NOT SET'))"
      fi
      echo "========================================"
      echo ""
    '';
  });

  # Version with the fix
  fixedVersion = pkgs.google-cloud-sdk.overrideAttrs (old: {
    name = "google-cloud-sdk-FIXED";
    
    # THE FIX: Set as derivation attribute (applies to all phases)
    PYTHONDONTWRITEBYTECODE = "1";
    
    installPhase = old.installPhase + ''
      # Also force imports to prove the fix works
      cd $out/google-cloud-sdk/lib
      export PYTHONPATH=$out/google-cloud-sdk/lib:$PYTHONPATH
      
      echo ""
      echo "Testing with PYTHONDONTWRITEBYTECODE=1..."
      python3 -c "import googlecloudsdk" 2>/dev/null || true
      python3 -c "import googlecloudsdk.core" 2>/dev/null || true
      
      PYCACHE_COUNT=$(find $out -type d -name __pycache__ | wc -l | tr -d ' ')
      echo "After fix: $PYCACHE_COUNT __pycache__ directories"
    '';
  });

in
pkgs.runCommand "forced-bug-reproduction"
  {
    outputs = [ "out" "report" ];
    preferLocalBuild = true;
  }
  ''
    {
      echo "=============================================="
      echo "FORCED __pycache__ Bug Reproduction"
      echo "=============================================="
      echo ""
      echo "This test explicitly triggers Python imports"
      echo "during the build to force the bug to manifest."
      echo ""
      
      echo "1. BUGGY VERSION (with forced imports):"
      echo "   Path: ${buggyForced}"
      echo ""
      
      BUGGY_PYCACHE=$(find ${buggyForced} -type d -name __pycache__ | wc -l | tr -d ' ')
      BUGGY_PYC=$(find ${buggyForced} -type f -name "*.pyc" | wc -l | tr -d ' ')
      
      if [ "$BUGGY_PYCACHE" -gt 0 ] || [ "$BUGGY_PYC" -gt 0 ]; then
        echo "   ✗ BUG CONFIRMED!"
        echo "     Found: $BUGGY_PYCACHE __pycache__ dirs, $BUGGY_PYC .pyc files"
        echo ""
        echo "   Sample locations:"
        find ${buggyForced} -name __pycache__ | head -5
        echo ""
        echo "   Sample .pyc files:"
        find ${buggyForced} -name "*.pyc" | head -5
        BUG_FOUND=1
      else
        echo "   ⚠ No bytecode found"
        echo "     This may indicate:"
        echo "     - Python imports are failing"
        echo "     - PYTHONDONTWRITEBYTECODE is set globally"
        echo "     - Filesystem restrictions"
        BUG_FOUND=0
      fi
      
      echo ""
      echo "2. FIXED VERSION (with PYTHONDONTWRITEBYTECODE=1):"
      echo "   Path: ${fixedVersion}"
      echo ""
      
      FIXED_PYCACHE=$(find ${fixedVersion} -type d -name __pycache__ | wc -l | tr -d ' ')
      FIXED_PYC=$(find ${fixedVersion} -type f -name "*.pyc" | wc -l | tr -d ' ')
      
      if [ "$FIXED_PYCACHE" -gt 0 ] || [ "$FIXED_PYC" -gt 0 ]; then
        echo "   ✗ Fix did not work!"
        echo "     Found: $FIXED_PYCACHE __pycache__ dirs, $FIXED_PYC .pyc files"
        FIX_WORKS=0
      else
        echo "   ✓ Fix works!"
        echo "     No bytecode found"
        FIX_WORKS=1
      fi
      
      echo ""
      echo "=============================================="
      echo "Analysis"
      echo "=============================================="
      echo ""
      
      if [ "$BUG_FOUND" -eq 1 ] && [ "$FIX_WORKS" -eq 1 ]; then
        echo "✓ SUCCESS: Bug reproduced and fix verified!"
        echo ""
        echo "Counts:"
        echo "  Buggy: $BUGGY_PYCACHE __pycache__ dirs, $BUGGY_PYC .pyc files"
        echo "  Fixed: $FIXED_PYCACHE __pycache__ dirs, $FIXED_PYC .pyc files"
        STATUS="SUCCESS"
      elif [ "$BUG_FOUND" -eq 0 ]; then
        echo "⚠ Bug did not manifest"
        echo ""
        echo "Troubleshooting:"
        echo ""
        echo "Check if PYTHONDONTWRITEBYTECODE is set in your environment:"
        echo "  $ python3 -c 'import os; print(os.environ.get(\"PYTHONDONTWRITEBYTECODE\"))'"
        echo ""
        echo "Try unsetting it and rebuilding:"
        echo "  $ unset PYTHONDONTWRITEBYTECODE"
        echo "  $ nix-build force-reproduce-bug.nix"
        echo ""
        echo "Or check Python's actual behavior:"
        echo "  $ python3 -c 'import sys; print(sys.dont_write_bytecode)'"
        echo ""
        STATUS="INCONCLUSIVE"
      else
        echo "✗ Unexpected results"
        STATUS="UNEXPECTED"
      fi
      
      echo ""
      echo "To inspect the builds:"
      echo "  Buggy: ${buggyForced}"
      echo "  Fixed: ${fixedVersion}"
      
    } | tee $report
    
    echo "$STATUS" > $out
    
    # Exit with success even if bug doesn't manifest
    # (we still want to see the report)
    exit 0
  ''
