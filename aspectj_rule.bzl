def _aspectj_library_impl(ctx):
    class_jar = ctx.outputs.class_jar

    compile_time_jars = depset(order = "topological")
    runtime_jars = depset(order = "topological")
    for dep in ctx.attr.deps:
        compile_time_jars = depset(
            transitive = [compile_time_jars, dep[JavaInfo].transitive_compile_time_jars],
        )
        runtime_jars = depset(
            transitive = [runtime_jars, dep[JavaInfo].transitive_runtime_jars],
        )
    compile_time_jars_list = compile_time_jars.to_list()

    aspect_libs_jars = depset(order = "topological")
    for lib in ctx.attr.aspect_libs:
        aspect_libs_jars = depset(
            transitive = [aspect_libs_jars, lib[JavaInfo].compile_jars],
        )

    # Cleaning build output directory
    build_output = class_jar.path + ".build_output"
    cmd = "set -e;rm -rf " + build_output + "\n"

    java_runtime = ctx.attr._jdk[java_common.JavaRuntimeInfo]
    java_path = "%s/bin/java" % java_runtime.java_home
    java_tools = "%s/lib/tools.jar" % java_runtime.java_home

    aspectj_tools_path = ctx.attr.aspectj_tools[JavaInfo].outputs.jars[0].class_jar.path
    ajc = java_path + " -cp " + java_tools + ctx.configuration.host_path_separator + aspectj_tools_path + " " + ctx.attr._xmx + " " + ctx.attr.ajc_main_class

    cmd += ajc

    if ctx.attr.ajc_opts:
        cmd += " " + ctx.attr.ajc_opts + " "
    if compile_time_jars:
        cmd += " -classpath " + cmd_helper.join_paths(ctx.configuration.host_path_separator, compile_time_jars)

    aspect_path = " -aspectpath " + cmd_helper.join_paths(ctx.configuration.host_path_separator, aspect_libs_jars)
    cmd += aspect_path
    cmd += " -inpath "
    for javaoutput in ctx.attr.input_jar[JavaInfo].outputs.jars:
        cmd += javaoutput.class_jar.path
    cmd += " -outjar " + class_jar.path

    ctx.actions.run_shell(
        inputs = (compile_time_jars_list + ctx.files._jdk + ctx.files.input_jar),
        outputs = [class_jar],
        mnemonic = "JavacBootstrap",
        command = cmd,
        use_default_shell_env = True,
    )

    runfiles = ctx.runfiles(collect_data = True)
    compile_time_jars = depset(transitive = [compile_time_jars], direct = [class_jar])
    runtime_jars = depset(transitive = [runtime_jars], direct = [class_jar])

    return [
        DefaultInfo(
            files = depset([class_jar]),
            runfiles = runfiles,
        ),
        JavaInfo(
            output_jar = class_jar,
            compile_jar = class_jar,
        ),
    ]

aspectj_library = rule(
    _aspectj_library_impl,
    attrs = {
        "_jdk": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
            providers = [java_common.JavaRuntimeInfo],
        ),
        "_xmx": attr.string(
            default = "-Xmx64M",
        ),
        "input_jar": attr.label(
            mandatory = True,
            allow_files = [".jar"],
        ),
        "aspectj_tools": attr.label(
            mandatory = True,
            allow_files = [".jar"],
        ),
        "ajc_main_class": attr.string(
            mandatory = True,
            doc = "the full path of the main class of aspectj tools",
        ),
        "ajc_opts": attr.string(
            mandatory = False,
            doc = "command options for ajc tool",
        ),
        "aspect_libs": attr.label_list(
            mandatory = True,
            allow_files = [".jar"],
        ),
        "deps": attr.label_list(
            allow_files = False,
            providers = [JavaInfo],
        ),
    },
    outputs = {
        "class_jar": "lib%{name}.jar",
    },
    fragments = ["java"],
)
