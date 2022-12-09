# Path library design

This document documents why the `lib.path` library is designed the way it is.

The purpose of this library is to process paths. It does not read files from the filesystem.
It exists to support the native Nix path value type with extra functionality.

Since the path value type implicitly imports paths from the "eval-time system" into the store,
this library explicitly doesn't support build-time or run-time paths, including paths to derivations.

Overall, this library works with two basic forms of paths:
- Absolute paths are represented with the Nix path value type. Nix automatically normalises these paths.
- Subpaths are represented with the string value type. This library normalises these paths as safely as possible. In the end, subpaths are intended to be used to refer to a specific file/directory nested in an absolute base directory. Subpaths are a more strict form of relative paths, notably [without supporting `..` references](#parents).

Notably absolute paths in a string value type are not supported, the use of the string value type for subpaths is only because the path value type doesn't support subpaths.

This library is designed to be as safe and intuitive as possible, throwing errors when operations are attempted that would produce surprising results, and giving the expected result otherwise.

This library is designed to work well as a dependency for the `lib.filesystem` and `lib.sources` library components. Contrary to these library components, `lib.path` is designed to not read any paths from the filesystem.

This library makes only these assumptions about paths and no others:
- `dirOf path` returns the path to the parent directory of `path`, unless `path` is the filesystem root, in which case `path` is returned
  - There can be multiple filesystem roots: `p == dirOf p` and `q == dirOf q` does not imply `p == q`
    - While there's only a single filesystem root in stable Nix, the [lazy trees PR](https://github.com/NixOS/nix/pull/6530) introduces [additional filesystem roots](https://github.com/NixOS/nix/pull/6530#discussion_r1041442173)
- `path + ("/" + string)` returns the path to the `string` subdirectory in `path`
  - If `string` contains no `/` characters, then `dirOf (path + ("/" + string)) == path`
  - If `string` contains no `/` characters, then `baseNameOf (path + ("/" + string)) == string`
- `path1 == path2` returns true only if `path1` points to the same filesystem path as `path2`

Notably we do not make the assumption that we can turn paths into strings using `toString path`.

## Design decisions

Each subsection here contains a decision along with arguments and counter-arguments for (+) and against (-) that decision.

### Leading dots for subpaths
[leading-dots]: #leading-dots-for-subpaths

Observing: Since subpaths are a form of relative paths, they can have a leading `./` to indicate it being a relative path, this is generally not necessary for tools though

Considering: Paths should be as explicit, consistent and unambiguous as possible

Decision: Returned subpaths should always have a leading `./`

<details>
<summary>Arguments</summary>

- :heavy_plus_sign: In shells, just running `foo` as a command wouldn't execute the file `foo`, whereas `./foo` would execute the file. In contrast, `foo/bar` does execute that file without the need for `./`. This can lead to confusion about when a `./` needs to be prefixed. If a `./` is always included, this becomes a non-issue. This effectively then means that paths don't overlap with command names.
- :heavy_plus_sign: Prepending with `./` makes the subpaths always valid as relative Nix path expressions
- :heavy_plus_sign: Using paths in command line arguments could give problems if not escaped properly, e.g. if a path was `--version`. This is not a problem with `./--version`. This effectively then means that paths don't overlap with GNU-style command line options
- :heavy_minus_sign: `./` is not required to resolve relative paths, resolution always has an implicit `./` in front
- :heavy_minus_sign: It's more pretty without the `./`, good for error messages and co.
  - :heavy_plus_sign: But similarly, it could be confusing whether something was even a path
    e.g. `foo` could be anything, but `./foo` is more clearly a path
- :heavy_plus_sign: Makes it more uniform with absolute paths (those always start with `/`)
  - :heavy_minus_sign: Not relevant though, this perhaps only simplifies the implementation a tiny bit
- :heavy_plus_sign: `find` also outputs results with `./`
  - :heavy_minus_sign: But only if you give it an argument of `.`. If you give it the argument `some-directory`, it won't prefix that
- :heavy_minus_sign: `realpath --relative-to` doesn't output `./`'s
  - :heavy_plus_sign: We don't need to return the same result though

</details>

### Representation of the current directory
[curdir]: #representation-of-the-current-directory

Observing: The subpath that produces the base directory can be represented with `.` or `./` or `./.`

Considering: Paths should be as consistent and unambiguous as possible

Decision: It should be `./.`

<details>
<summary>Arguments</summary>

- :heavy_plus_sign: `./` would be inconsistent with [the decision to not have trailing slashes](#trailing-slashes)
- :heavy_minus_sign: `.` is how `realpath` normalises paths
- :heavy_plus_sign: `.` can be interpreted as a shell command (it's a builtin for sourcing files in bash and zsh)
- :heavy_plus_sign: `.` would be the only path without a `/` and therefore not a valid Nix path in expressions
- :heavy_minus_sign: `./.` is rather long
  - :heavy_minus_sign: We don't require users to type this though, it's mainly just used as a library output.
    As inputs all three variants are supported for subpaths (and we can't do anything about absolute paths)
- :heavy_minus_sign: `builtins.dirOf "foo" == "."`, so `.` would be consistent with that
- :heavy_plus_sign: `./.` is consistent with the [decision to have leading `./`](#leading-dots)
- :heavy_plus_sign: `./.` is a valid Nix path expression, although this property does not hold for every relative path or subpath

</details>

### Subpath representation
[relrepr]: #subpath-representation

Observing: Subpaths can be represented as a string, a list with all the components like `[ "foo" "bar" ]` for `foo/bar`, or with an attribute set like `{ type = "subpath"; components = [ "foo" "bar" ]; }`

Considering: Paths should be as safe to use as possible, we should generate string outputs in the library and not encourage users to do that instead by returning lists

Decision: Paths are represented as strings

<details>
<summary>Arguments</summary>

- :heavy_plus_sign: It's simpler for the end user, as one doesn't need to make sure the path is in a string representation before it can be used
  - :heavy_plus_sign: Also `concatStringsSep "/"` might be used to turn a list subpath value into a string, which then breaks for `[]`
- :heavy_plus_sign: It doesn't encourage people to do their own path processing and instead use the library
  E.g. With lists it would be very easy to just use `lib.lists.init` to get the parent directory, but then it breaks for `.`, represented as `[ ]`
- :heavy_plus_sign: `+` is convenient and doesn't work on lists and attribute sets
  - :heavy_minus_sign: Shouldn't use `+` anyways, we export safer functions for path manipulation

</details>

### Parents
[parents]: #parents

Observing: Relative paths can have `..` components, which refer to the parent directory

Considering: Paths should be as safe and unambiguous as possible

Decision: `..` path components in string paths are not supported, neither as inputs nor as outputs. Hence, string paths are called subpaths, rather than relative paths.

<details>
<summary>Arguments</summary>

- :heavy_plus_sign: If we wanted relative paths to behave according to the "physical" interpretation (as a directory tree with relations between nodes), it would require resolving symlinks, since e.g. `foo/..` would not be the same as `.` if `foo` is a symlink.
  - :heavy_minus_sign: The "logical" interpretation is also valid (treating paths as a sequence of names), and is used by some software. It is simpler, and not using symlinks at all is safer.
  - :heavy_plus_sign: Mixing both models can lead to surprises.
  - :heavy_plus_sign: We can't resolve symlinks without filesystem access
  - :heavy_plus_sign: Nix also doesn't support reading symlinks at eval-time
  - :heavy_minus_sign: What is "proper behavior"? Why can't we just not handle these cases?
    - :heavy_plus_sign: E.g. `equals "foo" "foo/bar/.."` should those paths be equal?
      - :heavy_minus_sign: That can just return `false`, the paths are different, we don't need to check whether the paths point to the same thing
    - :heavy_plus_sign: E.g. `relativeTo /foo /bar == "../foo"`. If this is used like `/bar/../foo` in the end and `bar` is a symlink to somewhere else, this won't be accurate
      - :heavy_minus_sign: We could not support such ambiguous operations, or mark them as such, e.g. the normal `relativeTo` will error on such a case, but there could be `extendedRelativeTo` supporting that
- :heavy_minus_sign: `..` are a part of paths, a path library should therefore support it
  - :heavy_plus_sign: If we can prove that all such use cases are better done e.g. with runtime tools, the library not supporting it can nudge people towards that
    - :heavy_minus_sign: Can we prove that though?
- :heavy_minus_sign: We could allow ".." just in the beginning
  - :heavy_plus_sign: Then we'd have to throw an error for doing `append /some/path "../foo"`, making it non-composable
  - :heavy_plus_sign: The same is for returning paths with `..`: `relativeTo /foo /bar => "../foo"` would produce a non-composable path
- :heavy_plus_sign: We argue that `..` is not needed at the Nix evaluation level, since we'd always start evaluation from the project root and don't go up from there
  - :heavy_plus_sign: And `..` is supported in Nix paths, turning them into absolute paths
    - :heavy_minus_sign: This is ambiguous with symlinks though
- :heavy_plus_sign: If you need `..` for building or runtime, you can use build/run-time tooling to create those (e.g. `realpath` with `--relative-to`), or use absolute paths instead.
  This also gives you the ability to correctly handle symlinks

</details>

### Trailing slashes
[trailing-slashes]: #trailing-slashes

Observing: Subpaths can contain trailing slashes, like `foo/`, indicating that the path points to a directory and not a file

Considering: Paths should be as consistent as possible, there should only be a single normalisation for the same path

Decision: All functions remove trailing slashes in their results

<details>
<summary>Arguments</summary>

- :heavy_plus_sign: It allows normalisations to be unique, in that there's only a single normalisation for the same path
- Comparison to other frameworks to figure out the least surprising behavior:
  - :heavy_plus_sign: Nix itself doesn't preserve trailing newlines when parsing and appending its paths
  - :heavy_minus_sign: [Rust's std::path](https://doc.rust-lang.org/std/path/index.html) does preserve them during [construction](https://doc.rust-lang.org/std/path/struct.Path.html#method.new)
    - :heavy_plus_sign: Doesn't preserve them when returning individual [components](https://doc.rust-lang.org/std/path/struct.Path.html#method.components)
    - :heavy_plus_sign: Doesn't preserve them when [canonicalizing](https://doc.rust-lang.org/std/path/struct.Path.html#method.canonicalize)
  - :heavy_plus_sign: [Python 3's pathlib](https://docs.python.org/3/library/pathlib.html#module-pathlib) doesn't preserve them during [construction](https://docs.python.org/3/library/pathlib.html#pathlib.PurePath)
    - Notably it represents the individual components as a list internally
  - :heavy_minus_sign: [Haskell's filepath](https://hackage.haskell.org/package/filepath-1.4.100.0) has [explicit support](https://hackage.haskell.org/package/filepath-1.4.100.0/docs/System-FilePath.html#g:6) for handling trailing slashes
    - :heavy_minus_sign: Does preserve them for [normalisation](https://hackage.haskell.org/package/filepath-1.4.100.0/docs/System-FilePath.html#v:normalise)
  - :heavy_minus_sign: [NodeJS's Path library](https://nodejs.org/api/path.html) preserves trailing slashes for [normalisation](https://nodejs.org/api/path.html#pathnormalizepath)
    - :heavy_plus_sign: For [parsing a path](https://nodejs.org/api/path.html#pathparsepath) into its significant elements, trailing slashes are not preserved
- :heavy_plus_sign: Nix's builtin function `dirOf` gives an unexpected result for paths with trailing slashes: `dirOf "foo/bar/" == "foo/bar"`.
  Inconsistently, `baseNameOf` works correctly though: `baseNameOf "foo/bar/" == "bar"`.
  - :heavy_minus_sign: We are writing a path library to improve handling of paths though, so we shouldn't use these functions and discourage their use
- :heavy_minus_sign: Unexpected result when normalising intermediate paths, like `relative.normalise ("foo" + "/") + "bar" == "foobar"`
  - :heavy_plus_sign: Does this have a real use case?
  - :heavy_plus_sign: Don't use `+` to append paths, this library has a `join` function for that
    - :heavy_minus_sign: Users might use `+` out of habit though
- :heavy_plus_sign: The `realpath` command also removes trailing slashes
- :heavy_plus_sign: Even with a trailing slash, the path is the same, it's only an indication that it's a directory

</details>

## Other implementations and references

- [Rust](https://doc.rust-lang.org/std/path/struct.Path.html)
- [Python](https://docs.python.org/3/library/pathlib.html)
- [Haskell](https://hackage.haskell.org/package/filepath-1.4.100.0/docs/System-FilePath.html)
- [Nodejs](https://nodejs.org/api/path.html)
- [POSIX.1-2017](https://pubs.opengroup.org/onlinepubs/9699919799/nframe.html)
