# EchoNotes

EchoNotes is an iOS note-taking prototype that brings handwritten notes and spoken content together.

## Features

- Write and organize notes with Apple Pencil using PencilKit.
- Recognize handwriting with Apple Vision.
- Capture speech and transcribe it with Apple Speech.
- Explore summary and revision screens that compare notes with a transcript.

## AI configuration

The Together.ai integration is intentionally unavailable in the current client. An API key must not be embedded in an iOS app because app bundles can be inspected. To enable AI summaries safely, route requests through a server-side proxy that stores the credential outside this repository and applies appropriate authentication and rate limits.

## Requirements

- Xcode with Swift support
- iOS 18.1 or later

Open `EchoNotes.swiftpm` in Xcode to inspect or run the project. Grant microphone and speech-recognition permissions when prompted.

## Project status

This repository contains an experimental project. Device permissions, network access, and the configured AI backend affect which features can run.
