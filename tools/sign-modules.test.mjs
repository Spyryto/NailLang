import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash,generateKeyPairSync,verify} from 'node:crypto';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const signer = fileURLToPath(new URL('./sign-modules.mjs',import.meta.url));

test('signs exact module bytes with Ed25519; rejects edits, duplicates and overwrites',
  async () => {
  const folder = await mkdtemp(join(tmpdir(),'naillang-sign-'));
  try {
    const {privateKey,publicKey} = generateKeyPairSync('ed25519');
    const keyPath = join(folder,'key.pem');
    await writeFile(keyPath,privateKey.export({type:'pkcs8',format:'pem'}),{mode:0o600});
    const imageA = '{"format":"nailseed.runtime-module.v1","name":"Alpha"}';
    const imageB = '{"format":"nailseed.runtime-module.v1","name":"Beta"}';
    const a=join(folder,'a.json'),b=join(folder,'b.json'),
      out=join(folder,'signed.json');
    await writeFile(a,imageA);
    await writeFile(b,imageB);
    function command(extra = []) {
      return spawnSync(process.execPath,[signer,'--release','v0.42',
        '--key-id','test-issuer','--private-key',keyPath,'--out',out,
        ...extra],{encoding:'utf8'});
    }
    let run=command(['Beta='+b,'Alpha='+a]);
    assert.equal(run.status,0,run.stderr);
    const manifest=JSON.parse(await readFile(out,'utf8'));
    assert.deepEqual(manifest.modules.map(x=>x.name),['Alpha','Beta']);
    assert.equal(manifest.modules[0].sha256,
      createHash('sha256').update(imageA).digest('hex'));
    const canonical=['naillang.signed-modules.v1','release=v0.42',
      'key=test-issuer','count=2',
      ...manifest.modules.map(x=>x.name+'='+x.sha256),''].join('\n');
    assert.equal(verify(null,Buffer.from(canonical,'ascii'),publicKey,
      Buffer.from(manifest.signature,'base64')),true);
    assert.equal(verify(null,Buffer.from(canonical+'altered','ascii'),publicKey,
      Buffer.from(manifest.signature,'base64')),false);
    assert.notEqual(command(['Alpha='+a,'Beta='+b]).status,0,
      'refuses to overwrite an existing signed release');
    assert.notEqual(command(['Alpha='+a,'Alpha='+a]).status,0,
      'rejects duplicate module names');
    assert.notEqual(command(['Wrong='+a]).status,0,
      'checks image self-declared name');
  } finally {
    await rm(folder,{recursive:true,force:true});
  }
});
