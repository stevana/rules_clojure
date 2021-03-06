load("//rules:jar.bzl", _clojure_jar_impl = "clojure_jar_impl")
load("//rules:common.bzl", "CljInfo")
load("//rules:namespace.bzl", _clojure_ns_impl = "clojure_ns_impl")

def _clojure_path_impl(ctx):
    return [DefaultInfo(files = depset([]))]

clojure_namespace = rule(
    doc = "Define a clojure namespace. Produces no output on its own. Can be consumed by clojure_library. clojure_binary and clojure_repl currently need jars, that requirement may be lifted in the future",
    attrs = {
        "srcs": attr.label_keyed_string_dict(mandatory = True, doc = "a map of the .clj{,c,s} source files to their destination location on the classpath", allow_files = True),
        "deps": attr.label_list(default = [], providers = [[CljInfo], [JavaInfo]]),
        "aot": attr.string_list(default = [], doc = "namespaces that must be AOT'd in any clojure_library that includes this namespace")
    },
    provides = [CljInfo],
    toolchains = ["@rules_clojure//:toolchain"],
    implementation = _clojure_ns_impl,
)

_clojure_library = rule(
    doc = "Create a jar containing clojure sources. Optionally AOTs. The output jar will contain: .clj sources and transitive sources, and all compiled classes from AOTing. The output jar will depend on the transitive `deps` of all srcs & deps",
    attrs = {
        "aot": attr.string_list(default = [], allow_empty = True, doc = "Namespaces in classpath to compile. merged with `clojure_namespace.aot`"),
        "srcs": attr.label_list(mandatory = False, allow_empty = True, default = [], doc = "a list of source namespaces to include in the jar", providers=[[CljInfo]]),
        "deps": attr.label_list(default = []),
        "resources": attr.label_list(default = [], allow_files = True),
        "compiledeps": attr.label_list(default = ["@rules_clojure//src/rules_clojure:jar"]),
        "javacopts": attr.string_list(default = [], allow_empty = True, doc = "Optional javac compiler options")
    },
    provides = [JavaInfo],
    toolchains = ["@rules_clojure//:toolchain"],
    implementation = _clojure_jar_impl,
)

def clojure_library(*, name, srcs = [], aot = [], data=[], deps=[], javacopts=[], **kwargs):
    testonly = False
    if "testonly" in kwargs:
        testonly = kwargs["testonly"]
        kwargs.pop("testonly")

    clj_jar = name + ".cljsrc"
    native_deps_jar = name


    ## clojure libraries which have native library dependencies (eg
    ## libsodium) can't be defined via skylark rules, because the
    ## required provider, JavaNativeLibraryInfo, is only constructable
    ## via java, not skylark. Therefore, create a `java_library` that
    ## we can pass deps into, and make the clj jar  depend on it
    native.java_library(name = native_deps_jar,
                        runtime_deps = deps + [clj_jar],
                        data = data,
                        testonly = testonly,
                        javacopts = javacopts)

    _clojure_library(name = clj_jar,
                     srcs = srcs,
                     deps = deps,
                     aot = aot,
                     testonly = testonly,
                     javacopts = javacopts,
                     **kwargs)

def clojure_binary(name, **kwargs):
    deps = []
    runtime_deps = []
    if "deps" in kwargs:
        deps = kwargs["deps"]
        kwargs.pop("deps")

    if "runtime_deps" in kwargs:
        runtime_deps = kwargs["runtime_deps"]
        kwargs.pop("runtime_deps")

    native.java_binary(name=name,
                       runtime_deps = deps + runtime_deps,
                       **kwargs)

def clojure_repl(name, deps=[], ns=None, **kwargs):
    args = []

    if ns:
        args.extend(["-e", """\"(require '[{ns}]) (in-ns '{ns})\"""".format(ns = ns)])

    args.extend(["-e", "(clojure.main/repl)"])

    native.java_binary(name=name,
                       runtime_deps=deps,
                       jvm_flags=["-Dclojure.main.report=stderr"],
                       main_class = "clojure.main",
                       args = args,
                       **kwargs)

def clojure_test(name, *, test_ns, srcs=[], deps=[], **kwargs):
    # ideally the library name and the bin name would be the same. They can't be.
    # clojure src files would like to depend on `foo_test`, so mangle the test binary, not the src jar name
    jarname = name + ".cljtest"

    clojure_library(name=jarname, srcs = srcs, deps = deps, testonly = True)
    native.java_test(name=name,
                     runtime_deps = [jarname, "@rules_clojure//src/rules_clojure:testrunner"],
                     use_testrunner = False,
                     main_class="clojure.main",
                     jvm_flags=["-Dclojure.main.report=stderr"],
                     args = ["-m", "rules-clojure.testrunner", test_ns],
                     **kwargs)
