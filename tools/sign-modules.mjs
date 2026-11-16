#!/usr/bin/env node
/**
 * Offline deployment tool, not part of the Nail runtime build.
 *
 * Signs a manifest of exact compiled Nail module JSON bytes with an
 * independently managed Ed25519 PEM private key. No npm dependencies.
 *
 * Usage:
 *   node tools/sign-modules.mjs --release v0.42 --key-id release-2026 \
 *     --private-key /secure/ed25519.pem --out dist/signed-bundle.json \
 *     Saver=build/Saver.json Viewer=build/Viewer.json
 *
 * The public key shown on stdout must be installed into trusted HOST
 * configuration by a separate authenticated channel; never import trust
 * from the untrusted manifest being verified.
 */
import {readFile, writeFile} from 'node:fs/promises';
import {createHash, createPrivateKey, createPublicKey, sign} from 'node:crypto';
import {TextDecoder} from 'node:util';

const FORMAT = 'naillang.signed-modules.v1';
const MODULE_FORMAT = 'nailseed.runtime-module.v1';

function usage() {
  return 'Usage: node tools/sign-modules.mjs --release v0.42 --key-id ID '
    + '--private-key /secure/ed25519.pem --out bundle.json '
    + 'Name=image.json [Name=image.json ...]';
}

function parse(args) {
  if (args.includes('--help')) {
    console.log(usage());
    process.exit(0);
  }
  const flags = new Map();
  const items = [];
  for (let i = 0; i < args.length; i++) {
    const word = args[i];
    if (word.startsWith('--')) {
      if (!['--release','--key-id','--private-key','--out'].includes(word)
          || flags.has(word) || i + 1 >= args.length) {
        throw new Error('Invalid flag: ' + word);
      }
      flags.set(word, args[++i]);
    } else {
      items.push(word);
    }
  }
  if (flags.size !== 4 || items.length < 1 || items.length > 128) {
    throw new Error(usage());
  }
  const release = flags.get('--release');
  const keyId = flags.get('--key-id');
  if (!/^v[0-9]+\.[0-9]+(\.[0-9]+)?$/.test(release)
      || !/^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/.test(keyId)) {
    throw new Error('Invalid release or key identifier');
  }
  const names = new Set();
  const requests = items.map(item => {
    const i = item.indexOf('=');
    if (i < 1 || i === item.length - 1) {
      throw new Error('Expected module Name=path.json');
    }
    const name = item.slice(0,i);
    const path = item.slice(i+1);
    if (!/^[A-Za-z_][A-Za-z_0-9]*$/.test(name)
        || name === 'NailHost' || names.has(name)) {
      throw new Error('Invalid or duplicate module name');
    }
    names.add(name);
    return {name,path};
  });
  requests.sort((a,b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
  return {release,keyId,requests,privateKeyPath:flags.get('--private-key'),
    outPath:flags.get('--out')};
}

async function run(args) {
  const {release,keyId,requests,privateKeyPath,outPath} = parse(args);
  // The exact bytes written to disk are what the Haxe host must later load.
  const modules = await Promise.all(requests.map(async ({name,path}) => {
    const bytes = await readFile(path);
    if (bytes.length === 0 || bytes.length > 16000000) {
      throw new Error('Invalid module image size: ' + name);
    }
    // Reject malformed UTF-8, preventing a mismatch between the byte digest
    // and the Haxe runtime's decoded String representation.
    const source = new TextDecoder('utf-8',{fatal:true,ignoreBOM:true})
      .decode(bytes);
    if (!Buffer.from(source,'utf8').equals(bytes)) {
      throw new Error('Non-canonical UTF-8 module image: ' + name);
    }
    const image = JSON.parse(source);
    if (image?.format !== MODULE_FORMAT || image?.name !== name) {
      throw new Error('Module image name or format mismatch: ' + name);
    }
    return {name,sha256:createHash('sha256').update(bytes).digest('hex')};
  }));
  const canonical = [FORMAT,'release=' + release,'key=' + keyId,
    'count=' + modules.length,
    ...modules.map(({name,sha256}) => name + '=' + sha256),''].join('\n');
  const privateKey = createPrivateKey(await readFile(privateKeyPath));
  if (privateKey.asymmetricKeyType !== 'ed25519') {
    throw new Error('Signing key must use Ed25519');
  }
  const signature = sign(null,Buffer.from(canonical,'ascii'),privateKey)
    .toString('base64');
  const manifest = {
    format:FORMAT,algorithm:'Ed25519',release,keyId,modules,signature
  };
  // Refuse to overwrite an existing release manifest.
  await writeFile(outPath,JSON.stringify(manifest,null,2)+'\n',
    {flag:'wx',mode:0o644});
  const spki = createPublicKey(privateKey).export({format:'der',type:'spki'});
  // The trusted key must be distributed independently of this untrusted
  // generated artifact. Printing it does NOT install or authorize it.
  console.log('Signed manifest: ' + outPath);
  console.log('Public key for out-of-band trust configuration (Base64): '
    + spki.subarray(-32).toString('base64'));
}

run(process.argv.slice(2)).catch(error => {
  console.error('Signing refused: ' + error.message);
  process.exitCode = 1;
});
