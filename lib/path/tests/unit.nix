# Unit tests for lib.path functions. Use `nix-build` in this directory to
# run these
{ libpath }:
let
  lib = import libpath;
  inherit (lib.path) subpath;

  cases = lib.runTests {
    testSubpathNormaliseExample1 = {
      expr = subpath.normalise "foo//bar";
      expected = "./foo/bar";
    };
    testSubpathNormaliseExample2 = {
      expr = subpath.normalise "foo/./bar";
      expected = "./foo/bar";
    };
    testSubpathNormaliseExample3 = {
      expr = subpath.normalise "foo/bar";
      expected = "./foo/bar";
    };
    testSubpathNormaliseExample4 = {
      expr = subpath.normalise "foo/bar/";
      expected = "./foo/bar";
    };
    testSubpathNormaliseExample5 = {
      expr = subpath.normalise "foo/bar/.";
      expected = "./foo/bar";
    };
    testSubpathNormaliseExample6 = {
      expr = subpath.normalise ".";
      expected = "./.";
    };
    testSubpathNormaliseExample7 = {
      expr = (builtins.tryEval (subpath.normalise "foo/../bar")).success;
      expected = false;
    };
    testSubpathNormaliseExample8 = {
      expr = (builtins.tryEval (subpath.normalise "")).success;
      expected = false;
    };
    testSubpathNormaliseExample9 = {
      expr = (builtins.tryEval (subpath.normalise "/foo")).success;
      expected = false;
    };
    testSubpathNormaliseValidDots = {
      expr = subpath.normalise "./foo/.bar/.../baz...qux";
      expected = "./foo/.bar/.../baz...qux";
    };
    testSubpathNormaliseWrongType = {
      expr = (builtins.tryEval (subpath.normalise null)).success;
      expected = false;
    };
    testSubpathNormaliseTwoDots = {
      expr = (builtins.tryEval (subpath.normalise "..")).success;
      expected = false;
    };
  };
in
  if cases == [] then "Unit tests successful"
  else throw "Path unit tests failed: ${lib.generators.toPretty {} cases}"
