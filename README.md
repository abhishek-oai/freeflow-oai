<p align="center">
  <img src="Resources/AppIcon-Source.png" width="128" height="128" alt="FreeFlow icon">
</p>

<h1 align="center">FreeFlow</h1>

<p align="center">
  Free and open source alternative to <a href="https://wisprflow.ai">Wispr Flow</a>, <a href="https://superwhisper.com">Superwhisper</a>, and <a href="https://monologue.to">Monologue</a>.
</p>

<p align="center">
  <a href="https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow.dmg"><b>⬇ Download FreeFlow.dmg</b></a><br>
  <sub>Works on all Macs (Apple Silicon + Intel)</sub>
</p>

---

<p align="center">
  <img src="Resources/demo.gif" alt="FreeFlow demo" width="600">
</p>

I like the concept of apps like [Wispr Flow](https://wisprflow.ai/), [Superwhisper](https://superwhisper.com/), and [Monologue](https://www.monologue.to/) that use AI to add accurate and easy-to-use transcription to your computer, but they all charge fees of ~$10/month when the underlying AI models are free to use or cost pennies.

So over the weekend I vibe-coded my own free version!

It's called FreeFlow. Here's how it works:

1. Download the app from above or [click here](https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow.dmg)
2. Create an OpenAI API key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
3. Press and hold `Fn` anytime to start recording and have whatever you say pasted into the current text field

This build uses OpenAI's audio transcription endpoint with `gpt-4o-mini-transcribe` for direct voice-to-text transcription.

An added bonus is that there's no FreeFlow server, so no data is stored or retained - making it more privacy friendly than the SaaS apps. The only information that leaves your computer are the API calls to OpenAI for transcription.

### FAQ

**Why does this use OpenAI instead of a local transcription model?**

I love this idea, and originally planned to build FreeFlow using local models.

In practice, the UX is much better when transcription completes quickly after you release the push-to-talk key. Hosted speech models currently make that experience feel more reliable and more responsive on a wide range of Macs.

Some day!

## License

Licensed under the MIT license.
