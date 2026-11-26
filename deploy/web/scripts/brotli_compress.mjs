#!/usr/bin/env node
/* Brotli-compress one file for web_deploy/scripts/precompress_web.py.
 *
 * Node's zlib ships Brotli, which lets the release staging work on a Windows
 * dev PC without the Python `brotli` module. Called as:
 *     node brotli_compress.mjs <source> <destination> <quality 1-11>
 * The input is streamed so a 126 MB .pck does not need one large buffer; the
 * output file is complete or absent (the caller still does the atomic rename).
 */
import { createReadStream, createWriteStream, unlinkSync } from 'node:fs';
import { createBrotliCompress, constants } from 'node:zlib';
import { pipeline } from 'node:stream/promises';

async function main() {
  const [source, destination, qualityArg] = process.argv.slice(2);
  if (!source || !destination) {
    console.error('usage: node brotli_compress.mjs <source> <destination> [quality]');
    process.exit(2);
  }
  const quality = Math.max(1, Math.min(11, Number(qualityArg) || 9));
  const compressor = createBrotliCompress({
    params: {
      [constants.BROTLI_PARAM_QUALITY]: quality,
      [constants.BROTLI_PARAM_LGWIN]: 22,
      [constants.BROTLI_PARAM_SIZE_HINT]: 0,
    },
  });
  try {
    await pipeline(createReadStream(source), compressor, createWriteStream(destination));
  } catch (error) {
    try { unlinkSync(destination); } catch { /* nothing to clean up */ }
    console.error(`brotli_compress: ${source}: ${error.message}`);
    process.exit(1);
  }
}

await main();
