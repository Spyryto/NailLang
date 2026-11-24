import nail.HostTextGrants;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.NType;
import nail.Value;
import nail.Vm;

/** Minimal end-to-end NailHost example; no new FFI or compiler path. */
class HostInteropQuickstartTestMain {
  static function main():Void {
    // Nail source is a separate, editable file embedded by the .hxml targets.
    var source = haxe.Resource.getString('host_greeter_source');
    if (source == null) throw 'Missing embedded Nail example';
    var image = ModuleImage.encode(ModuleLinker.compilePublic({
      name:'Greeter', source:source, exports:['hello']
    }));

    var grants = new HostTextGrants();
    grants.grantFunction('Greeter','greet',TFunction(TText,TText),
      args -> switch (args[0]) {
        case Text(name): Text('Ciao, ' + name);
        case _: throw 'unexpected type: host bridge checks arguments';
      });

    var linked = ModuleLinker.linkImages([image],40000000,grants);
    var actual = Vm.toPlain(linked.invoke('Greeter','hello',Text('Nail')));
    if (actual != 'Ciao, Nail') throw 'Unexpected greeting: ' + actual;

    // A source-level import alone never grants host authority.
    var rejected = false;
    try ModuleLinker.linkImages([image],40000000,new HostTextGrants())
    catch (_:Dynamic) rejected = true;
    if (!rejected) throw 'Host import must require an explicit grant';

    trace(actual);
  }
}
