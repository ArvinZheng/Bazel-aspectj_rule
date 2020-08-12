def _aspectj_library_impl(ctx):
    class_jar = ctx.outputs.class_jar

    compile_time_jars_transitive = []
    runtime_jars_transitive = []
    exported_java_infos = []
    for dep in ctx.attr.deps:
        compile_time_jars_transitive += [dep[JavaInfo].transitive_compile_time_jars]
        runtime_jars_transitive += [dep[JavaInfo].transitive_runtime_jars]
        exported_java_infos.append(dep[JavaInfo])
    compile_time_jars = depset(
        transitive = compile_time_jars_transitive,
    )
    runtime_jars = depset(
        transitive = runtime_jars_transitive,
    )
    compile_time_jars_list = compile_time_jars.to_list()

    aspect_libs_jars_transitive = []
    for lib in ctx.attr.aspect_libs:
        aspect_libs_jars_transitive += [lib[JavaInfo].compile_jars]
    aspect_libs_jars = depset(
        transitive = aspect_libs_jars_transitive,
    )

    # Cleaning build output directory
    build_output = class_jar.path + ".build_output"
    cmd = "set -e;rm -rf " + build_output + "\n"

    java_runtime = ctx.attr._jdk[java_common.JavaRuntimeInfo]
    java_path = "%s/bin/java" % java_runtime.java_home
    java_tools = "%s/lib/tools.jar" % java_runtime.java_home

    aspectj_tools_path = ctx.attr.aspectj_tools[JavaInfo].outputs.jars[0].class_jar.path
    cp = ctx.configuration.host_path_separator.join([
        java_tools,
        aspectj_tools_path,
    ])

    # Building ajc parameters
    ajc_main_class = "org.aspectj.tools.ajc.Main"
    ajc_params = [java_path, "-cp", cp, ctx.attr._xmx, ajc_main_class]

    if ctx.attr.ajc_opts:
        ajc_params.append(ctx.attr.ajc_opts)
    if compile_time_jars:
        ajc_params.append("-classpath")
        ajc_params.append(cmd_helper.join_paths(ctx.configuration.host_path_separator, compile_time_jars))

    ajc_params.append("-aspectpath")
    ajc_params.append(cmd_helper.join_paths(ctx.configuration.host_path_separator, aspect_libs_jars))
    ajc_params.append("-inpath")
    for javaoutput in ctx.attr.input_jar[JavaInfo].outputs.jars:
        ajc_params.append(javaoutput.class_jar.path)
    ajc_params.append("-outjar")
    ajc_params.append(class_jar.path)

    ajc = " ".join(ajc_params)
    cmd += ajc

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
            exports = exported_java_infos,
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
