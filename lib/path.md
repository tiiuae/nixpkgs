# Path library design

This document explains why the `lib.path` library is designed the way it is.

The purpose of this library is to process [filesystem paths]. It does not read files from the filesystem.
It exists to support the native Nix [path value type] with extra functionality.

[filesystem paths]: https://en.m.wikipedia.org/wiki/Path_(computing)
[path value type]: https://nixos.org/manual/nix/stable/language/values.html#type-path

As an extension of the path value type, it inherits the same intended use cases and limitations:
- Only use paths to access files at evaluation time, such as the local project source.
- Paths cannot point to derivations, so they are unfit to represent dependencies.
- A path implicitly imports the referenced files into the Nix store when interpolated to a string. Therefore paths are not suitable to access files at build- or run-time, as you risk importing the path from the evaluation system instead.

Overall, this library works with two types of paths:
- Absolute paths are represented with the Nix [path value type]. Nix automatically normalises these paths.
- Subpaths are represented with the [string value type] since path value types don't support relative paths. This library normalises these paths as safely as possible. Absolute paths in strings are not supported.

  A subpath refers to a specific file or directory within an absolute base directory.
  It is a stricter form of a relative path, which notably must not start with `/` and [does not support `..` components][parents].

[string value type]: https://nixos.org/manual/nix/stable/language/values.html#type-string

This library is designed to be as safe and intuitive as possible, throwing errors when operations are attempted that would produce surprising results, and giving the expected result otherwise.

This library is designed to work well as a dependency for the `lib.filesystem` and `lib.sources` library components. Contrary to these library components, `lib.path` does not read any paths from the filesystem.

This library makes only these assumptions about paths and no others:
- `dirOf path` returns the path to the parent directory of `path`, unless `path` is the filesystem root, in which case `path` is returned.
  - There can be multiple filesystem roots: `p == dirOf p` and `q == dirOf q` does not imply `p == q`.
    - While there's only a single filesystem root in stable Nix, the [lazy trees feature](https://github.com/NixOS/nix/pull/6530) introduces [additional filesystem roots](https://github.com/NixOS/nix/pull/6530#discussion_r1041442173).
- `path + ("/" + string)` returns the path to the `string` subdirectory in `path`.
  - If `string` contains no `/` characters, then `dirOf (path + ("/" + string)) == path`.
  - If `string` contains no `/` characters, then `baseNameOf (path + ("/" + string)) == string`.
- `path1 == path2` returns `true` only if `path1` points to the same filesystem path as `path2`.

Notably we do not make the assumption that we can turn paths into strings using `toString path`.

## Design decisions

Each subsection here contains a decision along with arguments and counter-arguments for (+) and against (-) that decision.

### Leading dots for relative paths
[leading-dots]: #leading-dots-for-relative-paths

Observing: Since subpaths are a form of relative paths, they can have a leading `./` to indicate it being a relative path, this is generally not necessary for tools though.

Considering: Paths should be as explicit, consistent and unambiguous as possible.

Decision: Returned subpaths should always have a leading `./`.

<details>
<summary>Arguments</summary>

- :heavy_plus_sign: In shells, just running `foo` as a command wouldn't execute the file `foo`, whereas `./foo` would execute the file. In contrast, `foo/bar` does execute that file without the need for `./`. This can lead to confusion about when a `./` needs to be prefixed. If a `./` is always included, this becomes a non-issue. This effectively then means that paths don't overlap with command names.
- :heavy_plus_sign: Prepending with `./` makes the subpaths always valid as relative Nix path expressions.
- :heavy_plus_sign: Using paths in command line arguments could give problems if not escaped properly, e.g. if a path was `--version`. This is not a problem with `./--version`. This effectively then means that paths don't overlap with GNU-style command line options.
- :heavy_minus_sign: `./` is not required to resolve relative paths, resolution always has an implicit `./` as prefix.
- :heavy_minus_sign: It's less noisy without the `./`, e.g. in error messages.
  - :heavy_plus_sign: But similarly, it could be confusing whether something was even a path.
    e.g. `foo` could be anything, but `./foo` is more clearly a path.
- :heavy_plus_sign: Makes it more uniform with absolute paths (those always start with `/`).
  - :heavy_minus_sign: That is not relevant for practical purposes.
- :heavy_plus_sign: `find` also outputs results with `./`.
  - :heavy_minus_sign: But only if you give it an argument of `.`. If you give it the argument `some-directory`, it won't prefix that.
- :heavy_minus_sign: `realpath --relative-to` doesn't prefix relative paths with `./`.
  - :heavy_plus_sign: There is no need to return the same result as `realpath`.

</details>

### Representation of the current directory
[curdir]: #representation-of-the-current-directory

Observing: The subpath that produces the base directory can be represented with `.` or `./` or `./.`.

Considering: Paths should be as consistent and unambiguous as possible.

Decision: It should be `./.`.

<details>
<summary>Arguments</summary>

- :heavy_plus_sign: `./` would be inconsistent with [the decision to not persist trailing slashes][trailing-slashes].
- :heavy_minus_sign: `.` is how `realpath` normalises paths.
- :heavy_plus_sign: `.` can be interpreted as a shell command (it's a builtin for sourcing files in `bash` and `zsh`).
- :heavy_plus_sign: `.` would be the only path without a `/`. It could not be used as a Nix path expression, since those require at least one `/` to be parsed as such.
- :heavy_minus_sign: `./.` is rather long.
  - :heavy_minus_sign: We don't require users to type this though, as it's only output by the library.
    As inputs all three variants are supported for subpaths (and we can't do anything about absolute paths)
- :heavy_minus_sign: `builtins.dirOf "foo" == "."`, so `.` would be consistent with that.
- :heavy_plus_sign: `./.` is consistent with the [decision to have leading `./`][leading-dots].
- :heavy_plus_sign: `./.` is a valid Nix path expression, although this property does not hold for every relative path or subpath.

</details>

### Subpath representation
[relrepr]: #subpath-representation

Observing: Subpaths such as `foo/bar` can be represented in various ways:
- string: `"foo/bar"`
- list with all the components: `[ "foo" "bar" ]`
- attribute set: `{ type = "relative-path"; components = [ "foo" "bar" ]; }`

Considering: Paths should be as safe to use as possible. We should generate string outputs in the library and not encourage users to do that themselves.

Decision: Paths are represented as strings.

<details>
<summary>Arguments</summary>

- :heavy_plus_sign: It's simpler for the users of the library. One doesn't have to convert a path a string before it can be used.
  - :heavy_plus_sign: Naively converting the list representation to a string with `concatStringsSep "/"` would break for `[]`, requiring library users to be more careful.
- :heavy_plus_sign: It doesn't encourage people to do their own path processing and instead use the library.
  With a list representation it would seem easy to just use `lib.lists.init` to get the parent directory, but then it breaks for `.`, which would be represented as `[ ]`.
- :heavy_plus_sign: `+` is convenient and doesn't work on lists and attribute sets.
  - :heavy_minus_sign: Shouldn't use `+` anyways, we export safer functions for path manipulation.

</details>

### Parent directory
[parents]: #parent-directory

Observing: Relative paths can have `..` components, which refer to the parent directory.

Considering: Paths should be as safe and unambiguous as possible.

Decision: `..` path components in string paths are not supported, neither as inputs nor as outputs. Hence, string paths are called subpaths, rather than relative paths.

<details>
<summary>Arguments</summary>

- :heavy_plus_sign: If we wanted relative paths to behave according to the "physical" interpretation (as a directory tree with relations between nodes), it would require resolving symlinks, since e.g. `foo/..` would not be the same as `.` if `foo` is a symlink.
  - :heavy_minus_sign: The "logical" interpretation is also valid (treating paths as a sequence of names), and is used by some software. It is simpler, and not using symlinks at all is safer.
  - :heavy_plus_sign: Mixing both models can lead to surprises.
  - :heavy_plus_sign: We can't resolve symlinks without filesystem access.
  - :heavy_plus_sign: Nix also doesn't support reading symlinks at evaluation time.
  - :heavy_minus_sign: We could just not handle such cases, e.g. `equals "foo" "foo/bar/.. == false`. The paths are different, we don't need to check whether the paths point to the same thing.
    - :heavy_plus_sign: Assume we said `relativeTo /foo /bar == "../bar"`. If this is used like `/bar/../foo` in the end, and `bar` turns out to be a symlink to somewhere else, this won't be accurate.
      - :heavy_minus_sign: We could decide to not support such ambiguous operations, or mark them as such, e.g. the normal `relativeTo` will error on such a case, but there could be `extendedRelativeTo` supporting that.
- :heavy_minus_sign: `..` are a part of paths, a path library should therefore support it.
  - :heavy_plus_sign: If we can convincingly argue that all such use cases are better done e.g. with runtime tools, the library not supporting it can nudge people towards using those.
- :heavy_minus_sign: We could allow "..", but only in the prefix.
  - :heavy_plus_sign: Then we'd have to throw an error for doing `append /some/path "../foo"`, making it non-composable.
  - :heavy_plus_sign: The same is for returning paths with `..`: `relativeTo /foo /bar => "../bar"` would produce a non-composable path.
- :heavy_plus_sign: We argue that `..` is not needed at the Nix evaluation level, since we'd always start evaluation from the project root and don't go up from there.
  - :heavy_plus_sign: `..` is supported in Nix paths, turning them into absolute paths.
    - :heavy_minus_sign: This is ambiguous in the presence of symlinks.
- :heavy_plus_sign: If you need `..` for building or runtime, you can use build-/run-time tooling to create those (e.g. `realpath` with `--relative-to`), or use absolute paths instead.
  This also gives you the ability to correctly handle symlinks.

</details>

### Trailing slashes
[trailing-slashes]: #trailing-slashes

Observing: Subpaths can contain trailing slashes, like `foo/`, indicating that the path points to a directory and not a file.

Considering: Paths should be as consistent as possible, there should only be a single normalisation for the same path.

Decision: All functions remove trailing slashes in their results.

<details>
<summary>Arguments</summary>

- :heavy_plus_sign: It allows normalisations to be unique, in that there's only a single normalisation for the same path. If trailing slashes were preserved, both `foo/bar` and `foo/bar/` would be valid but different normalisations for the same path.
- Comparison to other frameworks to figure out the least surprising behavior:
  - :heavy_plus_sign: Nix itself doesn't support trailing slashes when parsing and doesn't preserve them when appending paths.
  - :heavy_minus_sign: [Rust's std::path](https://doc.rust-lang.org/std/path/index.html) does preserve them during [construction](https://doc.rust-lang.org/std/path/struct.Path.html#method.new).
    - :heavy_plus_sign: Doesn't preserve them when returning individual [components](https://doc.rust-lang.org/std/path/struct.Path.html#method.components).
    - :heavy_plus_sign: Doesn't preserve them when [canonicalizing](https://doc.rust-lang.org/std/path/struct.Path.html#method.canonicalize).
  - :heavy_plus_sign: [Python 3's pathlib](https://docs.python.org/3/library/pathlib.html#module-pathlib) doesn't preserve them during [construction](https://docs.python.org/3/library/pathlib.html#pathlib.PurePath).
    - Notably it represents the individual components as a list internally.
  - :heavy_minus_sign: [Haskell's filepath](https://hackage.haskell.org/package/filepath-1.4.100.0) has [explicit support](https://hackage.haskell.org/package/filepath-1.4.100.0/docs/System-FilePath.html#g:6) for handling trailing slashes.
    - :heavy_minus_sign: Does preserve them for [normalisation](https://hackage.haskell.org/package/filepath-1.4.100.0/docs/System-FilePath.html#v:normalise).
  - :heavy_minus_sign: [NodeJS's Path library](https://nodejs.org/api/path.html) preserves trailing slashes for [normalisation](https://nodejs.org/api/path.html#pathnormalizepath).
    - :heavy_plus_sign: For [parsing a path](https://nodejs.org/api/path.html#pathparsepath) into its significant elements, trailing slashes are not preserved.
- :heavy_plus_sign: Nix's builtin function `dirOf` gives an unexpected result for paths with trailing slashes: `dirOf "foo/bar/" == "foo/bar"`.
  Inconsistently, `baseNameOf` works correctly though: `baseNameOf "foo/bar/" == "bar"`.
  - :heavy_minus_sign: We are writing a path library to improve handling of paths though, so we shouldn't use these functions and discourage their use.
- :heavy_minus_sign: Unexpected result when normalising intermediate paths, like `relative.normalise ("foo" + "/") + "bar" == "foobar"`.
  - :heavy_plus_sign: This is not a practical use case though.
  - :heavy_plus_sign: Don't use `+` to append paths, this library has a `join` function for that.
    - :heavy_minus_sign: Users might use `+` out of habit though.
- :heavy_plus_sign: The `realpath` command also removes trailing slashes.
- :heavy_plus_sign: Even with a trailing slash, the path is the same, it's only an indication that it's a directory.

</details>

## Other implementations and references

- [Rust](https://doc.rust-lang.org/std/path/struct.Path.html)
- [Python](https://docs.python.org/3/library/pathlib.html)
- [Haskell](https://hackage.haskell.org/package/filepath-1.4.100.0/docs/System-FilePath.html)
- [Nodejs](https://nodejs.org/api/path.html)
- [POSIX.1-2017](https://pubs.opengroup.org/onlinepubs/9699919799/nframe.html)
