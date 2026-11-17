package nail;

/** An imported template macro must interpret its numeric literals under the
    same declared language version as the importing source. This includes
    transitive macro imports: the resolver checks every loaded module against
    the original compilation unit. No implicit modern upgrade of bare modules.
    Legacy Float and opt-in Exact remain distinct unversioned dialects. */
class MacroModuleDialect {
  public static function requireCompatible(importerVersion:Null<String>,
      importerExact:Bool, moduleSource:String, moduleName:String):Void {
    if (numeric.NumericDialect.isExact(moduleSource) != importerExact)
      throw 'Imported macro module uses incompatible numeric dialect: ' + moduleName;

    var moduleVersion = numeric.LanguageVersion.declared(moduleSource);
    if (moduleVersion != importerVersion)
      throw 'Imported macro module uses incompatible Nail version: ' + moduleName
        + ' (expected ' + (importerVersion == null ? 'unversioned' : importerVersion)
        + ', got ' + (moduleVersion == null ? 'unversioned' : moduleVersion) + ')';
  }
}
