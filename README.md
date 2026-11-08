VIYO

A creator-focused video platform combining short dramas, social video and AI-assisted filmmaking.

Website: https://viyo.site/app

VIYO brings viewers and creators together. VIYO Watch is the viewing and discovery experience for short dramas, series, films and creator videos. VIYO Studio gives creators tools to develop stories and produce AI-assisted video content, scene by scene.

The project is being developed as a connected mobile and web experience, supported by a separate Python backend.

Product areas

VIYO Watch

A video and short-drama platform with features including:

- Video feed and content discovery
- Short-drama and series browsing
- Episode-based series publishing
- Creator profiles and social interactions
- Likes, comments, sharing and messaging
- Continue-watching and watch progress
- Creator uploads and video playback
- Creator tools for promoting and improving content

VIYO Studio

An AI-assisted production workspace for creating dramas, episodes, short films and other video productions.

The implemented workflow includes:

- Starting a production from an idea or story brief
- AI-assisted script development and scene breakdown
- Character profiles and visual references
- Character voice selection and dialogue generation
- Scene image generation
- Optional AI-generated moving scenes
- Sound-effect selection and dialogue captions
- Video assembly and export
- Production credits and cost estimates
- Downloading finished productions

Studio supports different production approaches, including still-image scenes with generated dialogue audio and scenes generated as moving video. Optional background music can be added by the creator.

The system is designed to preserve character information and voice assignments across episodes, although generated visual and voice consistency still depends on the selected AI generation method.

Creator ownership

VIYO is designed around creator ownership rather than exclusive publishing.

Creators can download their own finished productions and share them on other platforms. Downloading does not automatically publish, delete or change the privacy status of the original VIYO content.

Technical architecture

Component| Technology
Mobile and web application| Flutter
Backend API| Python, FastAPI
Authentication and database| Supabase
File storage| Supabase Storage
Video delivery| Bunny Stream
AI integrations| Google Gemini and OpenAI
Video processing| FFmpeg
Background production jobs| Python worker
Error monitoring| Sentry integration

Related repositories

- Flutter application: https://github.com/ollie81/Viyo-
- AI backend: https://github.com/ollie81/viyo_ai
- Earlier MVP: https://github.com/ollie81/viyo_app

The earlier MVP is retained separately from the newer application.

Engineering work

The project involves building and connecting:

- A cross-platform Flutter interface
- Authenticated backend APIs
- Video upload, processing and playback workflows
- Creator and series data models
- AI generation and media-processing pipelines
- Credit accounting and cost estimation
- Background jobs and production status tracking
- Secure, ownership-checked creator downloads

Development status

VIYO is under active development.

The application and backend contain substantial implemented functionality. Creator Studio also has automated tests that exercise production workflows using simulated AI providers and a local PostgreSQL database.

Those tests do not, by themselves, establish that every real AI provider, payment integration or production deployment is fully operational. Live provider testing, deployment configuration and required database setup must be verified separately.

Project direction

The long-term goal is to make VIYO a place where creators can produce, publish and distribute their own video stories, while viewers can discover and watch content from creators around the world.

---

Created and developed by the project owner.olivier
