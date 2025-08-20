#!/usr/bin/env -S deno run --allow-all

// Kernel wrapper to debug message issues
import { readLines } from "https://deno.land/std/io/mod.ts";

const logFile = "/tmp/kernel-debug.log";

function log(message: string) {
  const timestamp = new Date().toISOString();
  Deno.writeTextFileSync(logFile, `${timestamp}: ${message}\n`, {
    append: true,
  });
}

log("Kernel wrapper started");

// Start the actual Deno kernel
const kernelProcess = new Deno.Command("deno", {
  args: ["jupyter", "--kernel"],
  stdin: "piped",
  stdout: "piped",
  stderr: "piped",
});

const kernel = kernelProcess.spawn();

// Forward stdin but log it
(async () => {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();

  for await (const chunk of Deno.stdin.readable) {
    try {
      const text = decoder.decode(chunk);
      log(
        `STDIN received (${chunk.length} bytes): ${text.substring(0, 200)}...`
      );

      // Check if it's valid JSON
      try {
        JSON.parse(text);
        log("Valid JSON received");
      } catch (e) {
        log(`Invalid JSON: ${e.message}`);
      }

      // Forward to kernel
      await kernel.stdin.getWriter().write(chunk);
    } catch (e) {
      log(`Error processing stdin: ${e.message}`);
    }
  }
})();

// Forward stdout
(async () => {
  for await (const chunk of kernel.stdout) {
    await Deno.stdout.write(chunk);
  }
})();

// Forward stderr and log it
(async () => {
  const decoder = new TextDecoder();
  for await (const chunk of kernel.stderr) {
    const text = decoder.decode(chunk);
    log(`STDERR: ${text}`);
    await Deno.stderr.write(chunk);
  }
})();

// Wait for kernel to exit
const status = await kernel.status;
log(`Kernel exited with status: ${status.code}`);
Deno.exit(status.code);
