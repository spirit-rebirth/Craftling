#!/usr/bin/env node

const mode = process.argv[2];
const useStdin = process.argv.includes('--stdin');
const rawArgs = process.argv.slice(3).filter(a => a !== '--stdin');

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => { data += chunk; });
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);
  });
}

function parseJsonSafe(name, value, fallback = {}) {
  if (!value) return fallback;
  try {
    return JSON.parse(value);
  } catch (error) {
    console.error(`Invalid JSON for ${name}: ${error.message}`);
    process.exit(1);
  }
}

function createConfirmPiePayload({ actorClass, actorName, build, placement }) {
  return {
    prompt: 'Build OK, editor open, actor placed. Proceed to PIE verification?',
    items: [
      { label: 'class', value: actorClass },
      { label: 'actor', value: actorName },
      { label: 'placement_status', value: placement?.status ?? 'unknown' },
      { label: 'resolved_class_path', value: placement?.resolved_class_path ?? '' },
    ],
    build: build ?? {},
    placement: placement ?? {},
  };
}

function createEvaluatePayload({ testStatus, testResults, logs }) {
  const resultCount = Array.isArray(testResults) ? testResults.length : 0;
  const logLines = Array.isArray(logs?.logs) ? logs.logs : [];
  const logCount = logLines.length;

  // Build a preview so the LLM can see actual evidence for the approval decision.
  // Lobster's extractApprovalRequest passes this through to the approval request.
  const previewParts = [];
  if (testStatus) previewParts.push(`Test status: ${testStatus.status ?? 'unknown'}`);
  if (Array.isArray(testResults) && testResults.length > 0) {
    previewParts.push('Test results:');
    for (const r of testResults.slice(0, 20)) {
      previewParts.push(`  ${r.passed ? 'PASS' : 'FAIL'}: ${r.name ?? 'unnamed'}`);
    }
  }
  if (logLines.length > 0) {
    previewParts.push(`Recent logs (last ${Math.min(logLines.length, 30)}):`)
    for (const line of logLines.slice(-30)) {
      previewParts.push(`  ${typeof line === 'string' ? line : JSON.stringify(line)}`);
    }
  }

  return {
    prompt: 'Review runtime evidence. Did the implementation pass?',
    items: [
      { label: 'test_status', value: testStatus?.status ?? 'unknown' },
      { label: 'result_count', value: String(resultCount) },
      { label: 'log_count', value: String(logCount) },
    ],
    preview: previewParts.join('\n').slice(0, 4000),
    test_status: testStatus ?? {},
    test_results: testResults ?? [],
    logs: logs ?? {},
  };
}

async function main() {
  if (!mode) {
    console.error('Usage: node ue-approval-payload.mjs <confirm_pie|evaluate> [--stdin | args...]');
    process.exit(1);
  }

  let payload;

  if (useStdin) {
    // New path: read a single JSON object from stdin
    const raw = await readStdin();
    let input;
    try {
      input = JSON.parse(raw);
    } catch (error) {
      console.error(`Invalid stdin JSON: ${error.message}`);
      console.error(`Raw stdin (first 500 chars): ${raw.slice(0, 500)}`);
      process.exit(1);
    }

    if (mode === 'confirm_pie') {
      payload = createConfirmPiePayload({
        actorClass: input.class ?? '',
        actorName: input.actor_name ?? '',
        build: input.build,
        placement: input.placement,
      });
    } else if (mode === 'evaluate') {
      payload = createEvaluatePayload({
        testStatus: input.test_status,
        testResults: input.test_results,
        logs: input.logs,
      });
    } else {
      console.error(`Unknown mode: ${mode}`);
      process.exit(1);
    }
  } else {
    // Legacy path: positional command-line arguments
    if (mode === 'confirm_pie') {
      payload = createConfirmPiePayload({
        actorClass: rawArgs[0] ?? '',
        actorName: rawArgs[1] ?? '',
        build: parseJsonSafe('build', rawArgs[2]),
        placement: parseJsonSafe('placement', rawArgs[3]),
      });
    } else if (mode === 'evaluate') {
      payload = createEvaluatePayload({
        testStatus: parseJsonSafe('test_status', rawArgs[0]),
        testResults: parseJsonSafe('test_results', rawArgs[1], []),
        logs: parseJsonSafe('logs', rawArgs[2]),
      });
    } else {
      console.error(`Unknown mode: ${mode}`);
      process.exit(1);
    }
  }

  console.log(JSON.stringify(payload));
}

main();
