import { NextResponse } from "next/server"
import { getTelosContext } from "@/lib/telos-data"
import { spawn } from "child_process"

export async function POST(request: Request) {
  try {
    const { message } = await request.json()

    if (!message) {
      return NextResponse.json(
        { error: "Message is required" },
        { status: 400 }
      )
    }

    // Load all TELOS context
    const telosContext = getTelosContext()

    const systemPrompt = `You are a helpful AI assistant with access to the user's complete Personal TELOS (Life Operating System).

${telosContext}

When answering questions:
- Reference specific information from the TELOS files above
- Be conversational and helpful
- If asked about goals, projects, beliefs, wisdom, etc., use the exact information from the relevant sections
- If information isn't in the TELOS data, say so clearly
- Keep responses concise but informative`

    // Use a configured OpenCode inference command instead of a missing legacy helper.
    const inferenceResult = await new Promise<{ success: boolean; output?: string; error?: string }>((resolve) => {
      const command = process.env.PAI_INFERENCE_CMD || process.env.OPENCODE_INFERENCE_CMD
      if (!command) {
        resolve({
          success: false,
          error: 'OpenCode inference adapter unavailable: set PAI_INFERENCE_CMD or OPENCODE_INFERENCE_CMD',
        })
        return
      }

      const proc = spawn('bash', ['-lc', command], {
        stdio: ['pipe', 'pipe', 'pipe'],
      })

      let stdout = ''
      let stderr = ''

      proc.stdin.write(JSON.stringify({ systemPrompt, userPrompt: message, level: 'fast', timeout: 60000 }))
      proc.stdin.end()

      proc.stdout.on('data', (data) => { stdout += data.toString() })
      proc.stderr.on('data', (data) => { stderr += data.toString() })

      proc.on('close', (code) => {
        if (code !== 0) {
          resolve({ success: false, error: stderr || `Process exited with code ${code}` })
        } else {
          resolve({ success: true, output: stdout.trim() })
        }
      })

      proc.on('error', (err) => {
        resolve({ success: false, error: err.message })
      })
    })

    if (!inferenceResult.success) {
      console.error("Inference Error:", inferenceResult.error)
      throw new Error(`Inference failed: ${inferenceResult.error}`)
    }

    const assistantMessage = inferenceResult.output

    if (!assistantMessage) {
      throw new Error("No response from inference")
    }

    return NextResponse.json({ response: assistantMessage })
  } catch (error) {
    console.error("Error in chat API:", error)
    return NextResponse.json(
      { error: "Failed to process request" },
      { status: 500 }
    )
  }
}
