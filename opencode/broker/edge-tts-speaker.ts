/**
 * Edge TTS speaker for the Pulse desktop renderer.
 *
 * Reads one utterance per stdin line. Lines may be plain text or JSON:
 *   {"text":"Done","language":"pt-BR"}
 *
 * The first real utterance resolves edge-tts, auto-installing it into
 * ~/.config/opencode/tts-venv unless PAI_EDGE_TTS_AUTO_INSTALL=false.
 */

import { existsSync, mkdirSync, unlinkSync } from 'fs';
import { join } from 'path';
import { homedir, tmpdir } from 'os';
import {
  parseSpeakerLine,
  resolveEdgeTtsConfig,
  resolveVoiceEnabled,
  type EdgeTtsResolvedConfig,
} from './edge-tts-lib.ts';

const DRY_RUN = process.argv.includes('--dry-run') || process.env.PAI_EDGE_TTS_DRY_RUN === '1';
const AUTO_INSTALL = !/^(0|false|no|off)$/i.test(process.env.PAI_EDGE_TTS_AUTO_INSTALL || 'true');
const VENV_DIR = process.env.PAI_EDGE_TTS_VENV || join(homedir(), '.config', 'opencode', 'tts-venv');
const VENV_PYTHON = join(
  VENV_DIR,
  process.platform === 'win32' ? 'Scripts' : 'bin',
  process.platform === 'win32' ? 'python.exe' : 'python',
);

function splitCommand(command: string): string[] {
  return command.split(/\s+/).map((part) => part.trim()).filter(Boolean);
}

async function run(cmd: string[], options: { stdout?: 'pipe' | 'ignore' | 'inherit'; stderr?: 'pipe' | 'ignore' | 'inherit' } = {}) {
  try {
    const proc = Bun.spawn(cmd, {
      stdout: options.stdout || 'pipe',
      stderr: options.stderr || 'pipe',
    });
    const exitCode = await proc.exited;
    const stdout = options.stdout === 'pipe' || options.stdout === undefined ? await new Response(proc.stdout).text().catch(() => '') : '';
    const stderr = options.stderr === 'pipe' || options.stderr === undefined ? await new Response(proc.stderr).text().catch(() => '') : '';
    return { exitCode, stdout, stderr };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { exitCode: 127, stdout: '', stderr: message };
  }
}

async function commandWorks(cmd: string[]): Promise<boolean> {
  const result = await run(cmd, { stdout: 'ignore', stderr: 'ignore' });
  return result.exitCode === 0;
}

async function findPython(): Promise<string | null> {
  for (const candidate of ['python3', 'python']) {
    if (await commandWorks([candidate, '--version'])) return candidate;
  }
  return null;
}

async function hasEdgeTtsModule(python: string): Promise<boolean> {
  return commandWorks([python, '-c', 'import edge_tts']);
}

let edgeCommandPromise: Promise<string[]> | null = null;

async function resolveEdgeCommand(): Promise<string[]> {
  if (process.env.PAI_EDGE_TTS_COMMAND) return splitCommand(process.env.PAI_EDGE_TTS_COMMAND);

  if (existsSync(VENV_PYTHON) && await hasEdgeTtsModule(VENV_PYTHON)) {
    return [VENV_PYTHON, '-m', 'edge_tts'];
  }

  if (await commandWorks(['edge-tts', '--version'])) return ['edge-tts'];
  if (await hasEdgeTtsModule('python3')) return ['python3', '-m', 'edge_tts'];
  if (await hasEdgeTtsModule('python')) return ['python', '-m', 'edge_tts'];

  if (!AUTO_INSTALL) {
    throw new Error('edge-tts is not installed and PAI_EDGE_TTS_AUTO_INSTALL=false');
  }

  const python = await findPython();
  if (!python) throw new Error('python3 or python is required to install edge-tts');

  mkdirSync(VENV_DIR, { recursive: true });
  let setup = await run([python, '-m', 'venv', VENV_DIR]);
  if (setup.exitCode !== 0) {
    throw new Error(`failed to create venv: ${setup.stderr || setup.stdout}`);
  }

  setup = await run([VENV_PYTHON, '-m', 'pip', 'install', '--quiet', 'edge-tts']);
  if (setup.exitCode !== 0) {
    throw new Error(`failed to install edge-tts: ${setup.stderr || setup.stdout}`);
  }

  return [VENV_PYTHON, '-m', 'edge_tts'];
}

async function getEdgeCommand(): Promise<string[]> {
  edgeCommandPromise ||= resolveEdgeCommand();
  return edgeCommandPromise;
}

let playerCommandPromise: Promise<string[]> | null = null;

async function resolvePlayerCommand(): Promise<string[]> {
  if (process.env.PAI_AUDIO_PLAYER_CMD) return splitCommand(process.env.PAI_AUDIO_PLAYER_CMD);
  if (process.platform === 'darwin' && existsSync('/usr/bin/afplay')) return ['/usr/bin/afplay'];
  if (await commandWorks(['ffplay', '-version'])) return ['ffplay', '-nodisp', '-autoexit', '-loglevel', 'quiet'];
  if (await commandWorks(['mpg123', '--version'])) return ['mpg123', '-q'];
  throw new Error('no audio player found; install ffmpeg/ffplay or mpg123, or set PAI_AUDIO_PLAYER_CMD');
}

async function getPlayerCommand(): Promise<string[]> {
  playerCommandPromise ||= resolvePlayerCommand();
  return playerCommandPromise;
}

async function speak(config: EdgeTtsResolvedConfig): Promise<void> {
  if (!config.text) return;
  if (DRY_RUN) {
    console.log(`[edge-tts] dry-run ${JSON.stringify({ language: config.language, voice: config.voice, text: config.text })}`);
    return;
  }

  const edgeCommand = await getEdgeCommand();
  const outputPath = join(tmpdir(), `pai-edge-tts-${Date.now()}-${Math.random().toString(36).slice(2)}.mp3`);

  try {
    const synth = await run([
      ...edgeCommand,
      '--voice', config.voice,
      '--rate', config.rate,
      '--volume', config.volume,
      '--text', config.text,
      '--write-media', outputPath,
    ]);
    if (synth.exitCode !== 0) {
      throw new Error(`edge-tts failed: ${synth.stderr || synth.stdout}`);
    }

    const player = await getPlayerCommand();
    const playback = await run([...player, outputPath], { stdout: 'ignore', stderr: 'pipe' });
    if (playback.exitCode !== 0) {
      throw new Error(`audio playback failed: ${playback.stderr}`);
    }
  } finally {
    try { unlinkSync(outputPath); } catch {}
  }
}

async function processLine(line: string): Promise<void> {
  const utterance = parseSpeakerLine(line);
  if (!utterance) return;
  if (!resolveVoiceEnabled()) {
    if (DRY_RUN) console.log('[edge-tts] dry-run skipped: voice disabled');
    return;
  }
  const config = resolveEdgeTtsConfig(utterance);
  try {
    await speak(config);
  } catch (error) {
    console.error(`[edge-tts] ${error instanceof Error ? error.message : String(error)}`);
  }
}

async function main(): Promise<void> {
  console.log(`[edge-tts] ready${DRY_RUN ? ' (dry-run)' : ''}`);
  const decoder = new TextDecoder();
  let buffer = '';

  for await (const chunk of Bun.stdin.stream()) {
    buffer += decoder.decode(chunk, { stream: true });
    let newline: number;
    while ((newline = buffer.indexOf('\n')) !== -1) {
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      await processLine(line);
    }
  }

  if (buffer.trim()) await processLine(buffer);
}

main().catch((error) => {
  console.error(`[edge-tts] fatal: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
