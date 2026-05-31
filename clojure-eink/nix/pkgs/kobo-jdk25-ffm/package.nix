{
  lib,
  jdk25_headless,
  libffi,
}:

jdk25_headless.overrideAttrs (old: {
  buildInputs = (old.buildInputs or [ ]) ++ [ libffi ];

  configureFlags = (old.configureFlags or [ ]) ++ [
    "--enable-fallback-linker"
    "--with-libffi-include=${lib.getDev libffi}/include"
    "--with-libffi-lib=${lib.getLib libffi}/lib"
    "--enable-libffi-bundling"
  ];

  postPatch = (old.postPatch or "") + ''
    # In cross builds, OpenJDK also creates a host buildjdk. The fallback
    # linker is only needed in the target JDK; otherwise the host buildjdk
    # tries to link against the target ARM libffi and fails.
    substituteInPlace make/modules/java.base/Lib.gmk \
      --replace-fail 'ifeq ($(ENABLE_FALLBACK_LINKER), true)' \
                     'ifeq ($(ENABLE_FALLBACK_LINKER)+$(CREATING_BUILDJDK), true+false)'
  '';
})
