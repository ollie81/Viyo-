#!/usr/bin/env python3
"""
Builds Viyo's public website: plain HTML pages that search engines and AI
crawlers can read without running JavaScript or signing in.

    python3 site_src/build_site.py        # writes ./site

The Flutter app itself is served at /app/ (see vercel.json). Every page
here is generated from the content below so titles, canonical URLs,
social cards, structured data and the sitemap stay in sync.

Only describe features that exist in the app. Anything not yet available
belongs in a clearly labelled "Not available yet" note.
"""
from __future__ import annotations

import html
import json
import os
from datetime import date

SITE = "https://www.viyo.site"
APP = "/app/"
NAME = "Viyo"
UPDATED = date.today().isoformat()
CONTACT_EMAIL = "olli1234x@gmail.com"   # same address the app's Copyright screen shows

DESCRIPTION = (
    "Viyo is a creator-focused video platform where people watch short dramas, series, movies and "
    "creators' videos, and creators can publish their own dramas and films, post their work and use "
    "AI tools, including one that turns a long video into ready-to-post short clips."
)
SHORT_DESCRIPTION = (
    "Watch and publish short dramas, series and movies, and turn your long videos into short clips with AI."
)
CREATOR_SHARE = "65%"        # episodes.py CREATOR_SHARE
MIN_WITHDRAWAL = "$10"       # wallet.py MIN_WITHDRAWAL_USD
COIN_USD = "$0.006"          # wallet.py COIN_USD

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "site")


def e(s: str) -> str:
    return html.escape(s, quote=True)


# ---------------------------------------------------------------- shared data

ORG = {
    "@type": "Organization",
    "@id": f"{SITE}/#organization",
    "name": NAME,
    "url": f"{SITE}/",
    "logo": f"{SITE}/assets/logo-512.png",
    "description": DESCRIPTION,
    "email": CONTACT_EMAIL,
}
WEBSITE = {
    "@type": "WebSite",
    "@id": f"{SITE}/#website",
    "name": NAME,
    "url": f"{SITE}/",
    "description": DESCRIPTION,
    "publisher": {"@id": f"{SITE}/#organization"},
    "inLanguage": "en",
}
APPLICATION = {
    "@type": "SoftwareApplication",
    "@id": f"{SITE}/#app",
    "name": NAME,
    "url": f"{SITE}{APP}",
    "applicationCategory": "MultimediaApplication",
    "operatingSystem": "Web browser",
    "description": DESCRIPTION,
    "publisher": {"@id": f"{SITE}/#organization"},
    # Free to join and use; some AI tools and later drama episodes use Viyo Coins.
    "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD",
               "description": "Free to join. Optional Viyo Coin packs and a Viyo Premium subscription."},
    "featureList": [
        "Short drama series with free first episodes",
        "Creators publish their own short dramas, series, movies and short films and keep 65% of coins from unlocks",
        "Feed of creator photos, videos and text posts",
        "AI Repurposer: turns a long video into up to 6 vertical short clips with captions",
        "AI caption tools: Hook Check, Caption Ideas, Improve with AI",
        "AI Video Coach",
        "Daily check-ins and missions that earn Viyo Coins",
    ],
}

NAV = [
    ("/features", "Features"),
    ("/creators", "For creators"),
    ("/ai-video-to-shorts", "AI video to shorts"),
    ("/short-drama", "Short dramas"),
    ("/publish", "Publish your film"),
    ("/faq", "FAQ"),
    ("/about", "About"),
]

FOOTER_LINKS = NAV + [("/contact", "Contact")]


# ---------------------------------------------------------------- page shell

def page(path: str, title: str, description: str, body: str, *, schema: list | None = None,
         crumbs: list | None = None, og_type: str = "website", is_home: bool = False) -> str:
    url = f"{SITE}{path if path != '/' else '/'}"
    graph = list(schema or [])
    if crumbs:
        graph.append({
            "@type": "BreadcrumbList",
            "itemListElement": [
                {"@type": "ListItem", "position": i + 1, "name": n, "item": f"{SITE}{p}"}
                for i, (p, n) in enumerate([("/", "Home")] + crumbs)
            ],
        })
    graph.append({
        "@type": "WebPage", "@id": f"{url}#webpage", "url": url, "name": title,
        "description": description, "isPartOf": {"@id": f"{SITE}/#website"},
        "about": {"@id": f"{SITE}/#app"}, "dateModified": UPDATED, "inLanguage": "en",
    })
    ld = json.dumps({"@context": "https://schema.org", "@graph": graph}, ensure_ascii=False, indent=1)
    current = ' aria-current="page"'
    nav = "".join(
        f'<a href="{p}"{current if p == path else ""}>{e(n)}</a>' for p, n in NAV)
    foot = "".join(f'<a href="{p}">{e(n)}</a>' for p, n in FOOTER_LINKS)
    # Returning app users and the installed home-screen app skip the landing page.
    home_redirect = ("""<script>
  (function () {
    try {
      var q = location.search;
      var standalone = window.matchMedia && window.matchMedia('(display-mode: standalone)').matches;
      if (q.indexOf('home') === -1 && (standalone || localStorage.getItem('viyo_app_seen') === '1')) {
        location.replace('/app/' + location.hash);
      }
    } catch (err) {}
  })();
  </script>
  """ if is_home else "")
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  {home_redirect}<title>{e(title)}</title>
  <meta name="description" content="{e(description)}">
  <link rel="canonical" href="{url}">
  <meta name="robots" content="index, follow, max-image-preview:large">
  <meta name="theme-color" content="#0B0B1A">
  <link rel="icon" type="image/png" href="/assets/favicon.png">
  <link rel="apple-touch-icon" href="/assets/logo-192.png">
  <meta property="og:site_name" content="{NAME}">
  <meta property="og:type" content="{og_type}">
  <meta property="og:url" content="{url}">
  <meta property="og:title" content="{e(title)}">
  <meta property="og:description" content="{e(description)}">
  <meta property="og:image" content="{SITE}/assets/og.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="Viyo: short dramas to watch and AI tools for creators">
  <meta property="og:locale" content="en_US">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{e(title)}">
  <meta name="twitter:description" content="{e(description)}">
  <meta name="twitter:image" content="{SITE}/assets/og.png">
  <link rel="stylesheet" href="/assets/site.css">
  <script type="application/ld+json">
{ld}
  </script>
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>
  <header class="top">
    <div class="wrap top-row">
      <a class="brand" href="/?home" aria-label="Viyo home">Viyo</a>
      <nav class="nav" aria-label="Main">{nav}</nav>
      <a class="btn btn-primary btn-sm" href="{APP}">Open Viyo</a>
    </div>
  </header>
  <main id="main">
{body}
  </main>
  <footer class="foot">
    <div class="wrap foot-grid">
      <div>
        <p class="brand">Viyo</p>
        <p class="muted small">{e(SHORT_DESCRIPTION)}</p>
      </div>
      <nav class="foot-links" aria-label="Footer">{foot}<a href="{APP}">Open the app</a></nav>
    </div>
    <div class="wrap"><p class="muted small">© {date.today().year} Viyo. Prices and features are described as they are today and may change.</p></div>
  </footer>
</body>
</html>
"""


def cta(text: str = "Open Viyo", sub: str = "Free to join. Your first AI clip video is free.") -> str:
    return f"""<section class="cta wrap">
      <h2>Try it yourself</h2>
      <p class="muted">{e(sub)}</p>
      <p><a class="btn btn-primary" href="{APP}">{e(text)}</a></p>
    </section>"""


def phone(src: str, alt: str) -> str:
    return (f'<figure class="phone"><img src="{src}" alt="{e(alt)}" width="520" height="1126" '
            f'fetchpriority="high" decoding="async"></figure>')


# ---------------------------------------------------------------- content

AI_TOOLS = [
    ("AI Repurposer", "Upload a long video and get up to 6 vertical short clips with captions and hooks.",
     "First video free, then 40 coins"),
    ("Hook Check", "Feedback on the opening line of your caption, the part that decides whether people keep reading.",
     "1 free a day, then 5 coins"),
    ("Caption Ideas", "Three caption options written from a rough idea.", "1 free a day, then 5 coins"),
    ("Improve with AI", "Polishes the wording of a caption you already wrote.", "1 free a day, then 5 coins"),
    ("Why This Worked", "A plain-language explanation of how one of your posts performed, based on its real numbers.",
     "1 free a day, then 5 coins"),
    ("Voice Consistency Check", "Flags a caption that sounds unlike the rest of your posts, with a rewrite in your voice.",
     "Automatic and free"),
    ("AI Video Coach", "A conversation about one specific video: what worked, what to fix, what to try next.",
     "1 free message a day, then 10 coins"),
    ("Weekly report, trends and ideas", "A weekly report card, content ideas for your niche and what is trending on Viyo.",
     "Automatic and free"),
    ("Glow Up (18+)", "Upload a selfie and get hairstyle, grooming, style and colour suggestions. Your photo is only saved if you choose to.",
     "10 coins"),
]

FAQ = [
    ("What is Viyo?", DESCRIPTION),
    ("Is Viyo free?",
     "Yes, Viyo is free to join and use. Watching the feed, posting, messaging, daily check-ins and missions cost "
     "nothing. Some AI tools and later drama episodes use Viyo Coins, which you can earn through check-ins and "
     "missions or buy in coin packs. Viyo Premium is an optional subscription for unlimited drama episodes."),
    ("Where can I use Viyo?",
     f"Viyo runs in your web browser on phones and computers at {SITE}{APP}. You can add it to your phone's home "
     "screen so it opens like an app."),
    ("What does the AI Repurposer do?",
     "You upload a longer video, such as a talk, interview, podcast or tutorial. Viyo transcribes it, works out what "
     "the whole video is about, finds the moments that make sense on their own, and turns up to 6 of them into "
     "vertical 9:16 clips with burned-in captions and a short hook line. Each clip is checked automatically for "
     "framing, sound level and caption timing before you see it."),
    ("How long can the video be, and how long are the clips?",
     "Videos up to about half an hour work. Clips are between about 12 and 60 seconds. You can choose Auto, Short "
     "(about 15 to 30 seconds, 40 at most), Medium (about 30 to 45 seconds, 55 at most) or Long (about 45 to 60 "
     "seconds). Only a standout moment may run past the Short or Medium limit, and no clip is cut before its point."),
    ("What does the AI Repurposer cost?",
     "Your first video is free (up to 10 minutes long). After that it costs 40 Viyo Coins per video. If no clip comes "
     "out good enough to publish, the coins are refunded automatically."),
    ("Does it work on videos without talking?",
     "Yes. For videos with little or no speech, such as cooking or travel footage with music, Viyo picks clips from "
     "the picture instead, and you can describe the look you want in a sentence."),
    ("Will Viyo make up clips if my video has no good moments?",
     "No. If no moment is strong enough to stand on its own, Viyo tells you so and refunds your coins rather than "
     "giving you weak clips."),
    ("What are short dramas on Viyo?",
     "Short dramas are series told in short episodes. On Viyo the first 3 episodes of a series are free. Later "
     "episodes are unlocked with Viyo Coins, or watched without coins with a Viyo Premium subscription. You can "
     "save series to a watchlist."),
    ("Can I publish my own drama, series, movie or film?",
     "Yes. From the Create menu, choose Upload Drama, Movie or Film. You can publish a short drama or series episode by "
     "episode, or a movie, short film or AI film as a single video, in vertical or landscape. You set the title, "
     "genre, cover and coin price."),
    ("Do creators earn from their dramas, movies and films?",
     f"Yes. When viewers spend coins to unlock your episodes or your movie, you keep {CREATOR_SHARE} of those coins as "
     f"earnings. Only coins viewers bought count; free coins from check-ins, missions and ads don't. Each earned coin "
     f"is worth {COIN_USD}, and you can withdraw from {MIN_WITHDRAWAL} to PayPal or mobile money; for now the Viyo team "
     "processes withdrawals by hand. The first 3 episodes of a series are free for viewers; a movie or short film is "
     "priced from the first watch."),
    ("How do I earn Viyo Coins?",
     "Through daily check-ins, streak bonuses and missions in the app. You can also buy coin packs on the web, from "
     "100 coins for $0.99 to 3,000 coins for $19.99."),
    ("Do I need an account?",
     "You can browse as a guest. You need a free account to post, message, buy coins or use the AI tools."),
    ("Is my content used to train AI?",
     "No. Viyo does not sell your content and does not use your uploaded photos or videos to train AI models. When "
     "you use an AI tool, the content you send to it is processed by an AI provider (OpenAI) to produce the result."),
    ("Is private content kept private?",
     "Videos you upload to the AI Repurposer are stored privately and deleted from the processing area after about "
     "a day; the finished clips are yours to post or download. You can delete your account and its data from "
     "Settings at any time."),
    ("What is not available yet?",
     "Glow Up hairstyle previews, where you would see a picture of yourself with a new hairstyle, are still in "
     "development. Glow Up text suggestions are available now."),
    ("How do I contact Viyo?", f"Email {CONTACT_EMAIL}. For copyright concerns, include a link to the content."),
]


def home() -> str:
    tools = "".join(
        f'<li><h3>{e(n)}</h3><p>{e(d)}</p><p class="price">{e(p)}</p></li>' for n, d, p in AI_TOOLS[:4])
    body = f"""
    <section class="hero wrap">
      <div class="hero-text">
        <p class="eyebrow">Short dramas · creator videos · AI clip tools</p>
        <h1>Watch short dramas. Turn your long videos into shorts.</h1>
        <p class="lead">{e(DESCRIPTION)}</p>
        <p class="actions">
          <a class="btn btn-primary" href="{APP}">Open Viyo</a>
          <a class="btn btn-ghost" href="/ai-video-to-shorts">How the AI clips work</a>
        </p>
        <p class="muted small">Free to join. Works in your browser on phone and computer.</p>
      </div>
      {phone("/assets/repurposer.webp", "The Viyo AI Repurposer screen: select a video, choose a clip length, run it free for your first video")}
    </section>

    <section class="wrap split" aria-labelledby="who">
      <h2 id="who" class="visually-hidden">Who Viyo is for</h2>
      <div class="card">
        <h3>For viewers</h3>
        <ul class="ticks">
          <li>Short drama series in quick episodes. The first 3 episodes of every series are free.</li>
          <li>A feed of videos, photos and posts from creators, with For You, Videos and Following tabs.</li>
          <li>Daily check-ins and missions that earn Viyo Coins.</li>
        </ul>
        <p><a href="/short-drama">About short dramas on Viyo →</a></p>
      </div>
      <div class="card">
        <h3>For creators</h3>
        <ul class="ticks">
          <li>Publish your own short drama, series, movie or short film, and earn coins when viewers unlock it.</li>
          <li>Post videos up to 40 minutes, photos and text.</li>
          <li>Turn one long video into up to 6 vertical clips with captions and hooks.</li>
          <li>AI help with hooks and captions, and plain feedback on how your posts did.</li>
        </ul>
        <p><a href="/creators">What Viyo offers creators →</a></p>
      </div>
    </section>

    <section class="wrap" aria-labelledby="bring">
      <div class="card feature-band">
        <div>
          <p class="eyebrow">For filmmakers and storytellers</p>
          <h2 id="bring">Bring your drama, movie or film to Viyo</h2>
          <p class="muted">Upload a short drama, a series, a movie, a short film or an AI film. You set the coin price, viewers watch the first 3 episodes of a series free, and you keep {CREATOR_SHARE} of the coins they spend to unlock the rest.</p>
        </div>
        <p class="actions"><a class="btn btn-primary" href="/publish">How publishing works</a></p>
      </div>
    </section>

    <section class="wrap" aria-labelledby="pipeline">
      <h2 id="pipeline">One long video in. Short clips out.</h2>
      <div class="timeline" aria-hidden="true">
        <div class="track"><span style="left:6%;width:7%"></span><span style="left:31%;width:5%"></span><span style="left:52%;width:8%"></span><span style="left:79%;width:6%"></span></div>
        <div class="track-labels"><span>0:00</span><span>your video</span><span>30:00</span></div>
        <div class="clips"><i></i><i></i><i></i><i></i></div>
      </div>
      <ol class="steps">
        <li><strong>Upload</strong> a talk, interview, podcast or tutorial, up to about half an hour.</li>
        <li><strong>Viyo understands the whole video</strong>: what it is about, who is speaking, and where each thought starts and ends.</li>
        <li><strong>It picks moments that stand on their own</strong> and cuts each one on a complete sentence.</li>
        <li><strong>Each clip is edited</strong> to 9:16 with captions and a hook line, then checked for framing, sound and caption timing.</li>
        <li><strong>You watch, download or post</strong> the clips you like.</li>
      </ol>
      <p><a class="btn btn-ghost" href="/ai-video-to-shorts">Read how it works</a></p>
    </section>

    <section class="wrap" aria-labelledby="tools">
      <h2 id="tools">AI tools built into the app</h2>
      <ul class="grid">{tools}</ul>
      <p><a href="/features">See every feature and its price →</a></p>
    </section>
    {cta()}
"""
    return page("/", "Viyo: Short Dramas and AI Video-to-Shorts for Creators",
                "Watch short drama series and creator videos, and turn your long videos into vertical short "
                "clips with captions using AI. Free to join.",
                body, schema=[ORG, WEBSITE, APPLICATION], is_home=True)


def features() -> str:
    rows = "".join(f"<tr><th scope=\"row\">{e(n)}</th><td>{e(d)}</td><td class=\"nowrap\">{e(p)}</td></tr>"
                   for n, d, p in AI_TOOLS)
    body = f"""
    <section class="wrap prose">
      <p class="eyebrow">Features</p>
      <h1>Everything you can do on Viyo today</h1>
      <p class="lead">This page lists what is available now. Anything still in development is marked as such.</p>

      <h2>Watch</h2>
      <ul class="ticks">
        <li><strong>Short drama series.</strong> Browse by type (short drama, series, movie, short film), by New, Popular or Hot, and by genre. The first 3 episodes of a series are free.</li>
        <li><strong>Watchlist.</strong> Save series to come back to.</li>
        <li><strong>Feed.</strong> For You, Videos and Following tabs with videos, photos and text posts from creators.</li>
        <li><strong>Discover.</strong> Search for creators and see new series and trending dramas.</li>
      </ul>

      <h2>Create and connect</h2>
      <ul class="ticks">
        <li><strong>Post</strong> text, photos, or videos up to 40 minutes.</li>
        <li><strong>Publish your own titles:</strong> short dramas, series, movies, short films and AI films. You set the coin price and keep {CREATOR_SHARE} of the coins from unlocks. <a href="/publish">How it works</a>.</li>
        <li><strong>Likes, comments, follows and direct messages.</strong></li>
        <li><strong>Coin gifts</strong> to creators you like.</li>
        <li><strong>Boosts:</strong> Boost Post (30 coins), Discover Spotlight (25 coins) and Boost Series (60 coins) give your work extra visibility on Viyo.</li>
        <li><strong>Leaderboard and invites.</strong> See top creators and invite friends.</li>
      </ul>

      <h2>AI tools</h2>
    </section>
    <div class="wrap table-wrap">
      <table>
        <thead><tr><th scope="col">Tool</th><th scope="col">What it does</th><th scope="col">Price</th></tr></thead>
        <tbody>{rows}</tbody>
      </table>
    </div>
    <section class="wrap prose">
      <h2>Viyo Coins and Premium</h2>
      <ul class="ticks">
        <li><strong>Earn coins</strong> with daily check-ins, streak bonuses and missions.</li>
        <li><strong>Buy coin packs</strong> on the web: 100 coins for $0.99, 550 for $4.99, 1,200 for $9.99, or 3,000 for $19.99.</li>
        <li><strong>Viyo Premium</strong> is an optional subscription (weekly, monthly or yearly) for unlimited drama episodes without coins.</li>
      </ul>

      <h2>Not available yet</h2>
      <ul class="plain">
        <li><strong>Glow Up hairstyle previews</strong>, a picture of you with a suggested hairstyle, are in development. Glow Up text suggestions are available now.</li>
      </ul>
    </section>
    {cta()}
"""
    return page("/features", "Viyo Features: Short Dramas, Creator Feed and AI Tools",
                "Every feature on Viyo today, with prices: short drama series, a creator feed, messaging, coins "
                "and AI tools like the AI Repurposer and Hook Check.",
                body, schema=[APPLICATION], crumbs=[("/features", "Features")])


def creators() -> str:
    body = f"""
    <section class="wrap hero hero-tight">
      <div class="hero-text">
        <p class="eyebrow">For creators</p>
        <h1>Make more from every video you film</h1>
        <p class="lead">Viyo gives creators a place to post and tools that do the slow parts: finding the best moments in a long video, cutting them into shorts, and helping with hooks and captions.</p>
        <p class="actions"><a class="btn btn-primary" href="{APP}">Start creating</a></p>
      </div>
      {phone("/assets/create_menu.webp", "The Viyo Create menu: Make Clips with AI, Upload Photo or Video, Upload Short Drama, Create or Join Challenge")}
    </section>
    <section class="wrap prose">
      <h2>What you can do</h2>
      <ul class="ticks">
        <li><strong>Turn long videos into shorts.</strong> The AI Repurposer finds up to 6 moments that work on their own and edits each into a vertical clip with captions and a hook. <a href="/ai-video-to-shorts">How it works</a>.</li>
        <li><strong>Post anything.</strong> Videos up to 40 minutes, photos and text posts.</li>
        <li><strong>Publish your drama or movie.</strong> Short dramas, series, movies, short films and AI films. You set the coin price and keep {CREATOR_SHARE} of the coins viewers spend to unlock it. <a href="/publish">How publishing works</a>.</li>
        <li><strong>Write better hooks and captions.</strong> Hook Check, Caption Ideas and Improve with AI each have one free use a day.</li>
        <li><strong>Learn from your numbers.</strong> Why This Worked explains a post's performance from its real stats, and a weekly report card arrives automatically.</li>
        <li><strong>Get noticed.</strong> Boost a post or a series, or appear in Discover Spotlight, using coins.</li>
        <li><strong>Earn support.</strong> Viewers can send you coin gifts.</li>
      </ul>

      <h2>Who it suits</h2>
      <p>Podcasters, educators, coaches, interviewers and anyone who records long-form talking videos and wants short clips for TikTok, Instagram Reels, YouTube Shorts or Viyo itself, plus short drama makers looking for an audience that watches series episode by episode.</p>

      <h2>What it costs</h2>
      <p>Joining and posting are free. Your first AI Repurposer video is free (up to 10 minutes), then 40 coins per video, refunded automatically if no clip is good enough to publish. See <a href="/features">all prices</a>.</p>
    </section>
    {cta("Start creating")}
"""
    return page("/creators", "Viyo for Creators: Post, Publish Dramas and Make Shorts with AI",
                "Post videos and short dramas, turn long videos into short clips with AI, and write better hooks "
                "and captions. Free to join; first AI clip video free.",
                body, schema=[APPLICATION], crumbs=[("/creators", "For creators")])


def ai_shorts() -> str:
    body = f"""
    <section class="wrap hero hero-tight">
      <div class="hero-text">
        <p class="eyebrow">AI video to shorts</p>
        <h1>Turn a long video into short clips that make sense on their own</h1>
        <p class="lead">Upload a talk, interview, podcast or tutorial. Viyo's AI Repurposer finds up to 6 complete moments and edits each into a vertical clip with captions and a hook, ready to post.</p>
        <p class="actions"><a class="btn btn-primary" href="{APP}">Try it free</a></p>
        <p class="muted small">Your first video is free (up to 10 minutes). Then 40 Viyo Coins per video.</p>
      </div>
      {phone("/assets/repurposer.webp", "The Viyo AI Repurposer screen with clip length options")}
    </section>

    <section class="wrap prose">
      <h2>How it works</h2>
      <ol class="steps">
        <li><strong>Transcribe.</strong> Every word is transcribed with timings, so cuts land between sentences, not in the middle of a word.</li>
        <li><strong>Understand the whole video.</strong> Viyo maps the topics, tells speakers apart by voice, and notes where the camera cuts, so it knows what each part means in context.</li>
        <li><strong>Find standalone moments.</strong> The AI scores candidate moments on hook, curiosity, emotion, completeness, how well they stand alone, and what a viewer takes away. Moments that open mid-conversation or end before their payoff are dropped or extended.</li>
        <li><strong>Editor review.</strong> A second pass checks each pick the way an editor would: does it open on its hook and end on a complete thought?</li>
        <li><strong>Edit.</strong> Each clip is cropped to 9:16 following the speaker, captioned word by word, given a short hook line, and its sound is levelled.</li>
        <li><strong>Quality check.</strong> Clips are checked for format, framing, black bars, loudness, silence and caption timing. A clip that fails is replaced by the next-best moment.</li>
      </ol>

      <h2>Clip length</h2>
      <p>Choose <strong>Auto</strong>, <strong>Short</strong> (about 15–30 seconds, 40 at most), <strong>Medium</strong> (about 30–45 seconds, 55 at most) or <strong>Long</strong> (about 45–60 seconds). A clip can be as short as 15 seconds when the point lands in that time. Only a standout moment may run past the Short or Medium limit; otherwise the AI finds a tighter moment that still opens on its hook and ends on its point. No clip is longer than 60 seconds.</p>

      <h2>Videos without talking</h2>
      <p>For cooking, travel or music videos with little or no speech, Viyo picks moments from the picture instead, and you can describe the look you want, for example "a slow-motion sunset walk on the beach".</p>

      <h2>What you get</h2>
      <ul class="ticks">
        <li>Up to 6 vertical 1080×1920 clips, as many as the video genuinely supports.</li>
        <li>Burned-in captions, a hook line, a suggested caption and hashtags for each clip.</li>
        <li>A score and a short reason for each pick.</li>
        <li>Preview, download, share to other apps, or post to Viyo.</li>
      </ul>

      <h2>Limits and honesty</h2>
      <ul class="plain">
        <li>Videos up to about half an hour and 500 MB.</li>
        <li>If no moment is strong enough to stand on its own, you get no clips and your coins back, never filler.</li>
        <li>Your uploaded video is stored privately and removed from the processing area after about a day.</li>
      </ul>
    </section>
    {cta("Try it free")}
"""
    return page("/ai-video-to-shorts", "AI Video to Shorts: Turn Long Videos into Clips | Viyo",
                "Turn a long talk, interview, podcast or tutorial into up to 6 vertical short clips with captions "
                "and hooks. Choose the clip length. First video free.",
                body, schema=[APPLICATION], crumbs=[("/ai-video-to-shorts", "AI video to shorts")])


def short_drama() -> str:
    body = f"""
    <section class="wrap prose">
      <p class="eyebrow">Short dramas</p>
      <h1>Short drama series, one quick episode at a time</h1>
      <p class="lead">Short dramas are stories told in short episodes made for watching on your phone. On Viyo you can browse series, watch the first episodes free, and follow the ones you like.</p>
      <p class="actions"><a class="btn btn-primary" href="{APP}">Watch on Viyo</a></p>

      <h2>Watching</h2>
      <ul class="ticks">
        <li><strong>First 3 episodes free</strong> in every series.</li>
        <li><strong>Later episodes</strong> are unlocked with Viyo Coins, or watched without coins with Viyo Premium.</li>
        <li><strong>Browse</strong> by type (short drama, series, movie, short film), by New, Popular or Hot, and by genre such as drama, revenge and romance.</li>
        <li><strong>Watchlist</strong> to save series for later.</li>
      </ul>

      <h2>Publish your own</h2>
      <p>Anyone can bring their work to Viyo: short dramas, series, movies, short films and AI films. You set the coin price, keep {CREATOR_SHARE} of the coins from unlocks, and can boost a title so more viewers find it. <a href="/publish">How publishing works</a>.</p>

      <h2>Coins and Premium</h2>
      <p>Coins come from daily check-ins and missions, or coin packs from $0.99. Viyo Premium is an optional weekly, monthly or yearly subscription for unlimited episodes.</p>
    </section>
    {cta("Watch on Viyo", "Free to join. The first 3 episodes of every series are free.")}
"""
    return page("/short-drama", "Watch Short Drama Series on Viyo: First 3 Episodes Free",
                "Watch short drama series on Viyo in quick episodes made for your phone. The first 3 episodes of "
                "every series are free; creators can publish their own episodes.",
                body, schema=[APPLICATION], crumbs=[("/short-drama", "Short dramas")])


def publish() -> str:
    body = f"""
    <section class="wrap hero hero-tight">
      <div class="hero-text">
        <p class="eyebrow">Publish on Viyo</p>
        <h1>Bring your drama, series, movie or film to Viyo</h1>
        <p class="lead">Made a short drama, a web series, a movie or a film? Publish it on Viyo, set your own price, and earn coins every time a viewer unlocks it.</p>
        <p class="actions"><a class="btn btn-primary" href="{APP}">Publish your first title</a></p>
        <p class="muted small">Free to publish. In the app: tap + then Upload Drama, Movie or Film.</p>
      </div>
      {phone("/assets/create_menu.webp", "The Viyo Create menu, where creators upload a drama, movie or film")}
    </section>

    <section class="wrap prose">
      <h2>What you can publish</h2>
      <ul class="ticks">
        <li><strong>Short dramas and series</strong>, published episode by episode. Viewers watch the first 3 episodes free, then unlock the rest.</li>
        <li><strong>Movies and short films</strong>, as a single video, priced from the first watch.</li>
        <li><strong>AI films</strong>, made with AI tools, listed in their own category.</li>
        <li>Vertical or landscape, with your own title, genre, cover image and description.</li>
      </ul>

      <h2>How you earn</h2>
      <ol class="steps">
        <li><strong>You set the price</strong> in Viyo Coins, per episode or for the whole movie.</li>
        <li><strong>Viewers unlock</strong> your episodes or movie with coins.</li>
        <li><strong>You keep {CREATOR_SHARE}</strong> of the coins they bought and spend on your title, added to your Wallet in dollars. Each earned coin is worth {COIN_USD}. Free coins from check-ins, missions and ads don't count.</li>
        <li><strong>Withdraw from {MIN_WITHDRAWAL}</strong> to PayPal or mobile money (MTN, Airtel and others). For now the Viyo team sends payouts by hand.</li>
      </ol>
      <p class="muted small">Viewers with Viyo Premium can watch episodes without spending coins.</p>

      <h2>Getting viewers</h2>
      <ul class="ticks">
        <li>Your title appears in the Dramas tab, where viewers browse by type, genre and New, Popular or Hot.</li>
        <li><strong>Boost Series</strong> (60 coins) puts your title in front of more viewers.</li>
        <li>Every episode and post has its own share link with a proper preview for WhatsApp, X and Facebook.</li>
        <li>Use the <a href="/ai-video-to-shorts">AI Repurposer</a> to cut trailers and highlight clips for TikTok, Reels and Shorts.</li>
        <li>Series analytics show how each episode is doing.</li>
      </ul>

      <h2>What you need</h2>
      <ul class="plain">
        <li>A free Viyo account.</li>
        <li>The rights to everything you upload. Don't upload work that belongs to someone else.</li>
      </ul>
    </section>
    {cta("Publish your first title", "Free to publish. Viewers get the first 3 episodes of a series free.")}
"""
    return page("/publish", "Publish Your Short Drama, Series, Movie or Film on Viyo",
                "Publish your own short drama, series, movie or film on Viyo. Set your coin price and keep "
                "65% of the coins viewers spend to unlock it.",
                body, schema=[APPLICATION], crumbs=[("/publish", "Publish your film")])


def about() -> str:
    body = f"""
    <section class="wrap prose">
      <p class="eyebrow">About</p>
      <h1>About Viyo</h1>
      <p class="lead">{e(DESCRIPTION)}</p>

      <h2>Why Viyo exists</h2>
      <p>Most creators record far more than they can edit. A one-hour conversation might hold five great moments, but finding and cutting them takes hours. Viyo was built so creators can spend their time making things, while the app handles finding the moments, cutting them into shorts and helping with the words around them. Alongside the tools, Viyo is a place to watch: short drama series and creator videos in one feed.</p>

      <h2>What Viyo is today</h2>
      <ul class="ticks">
        <li>A web app for phones and computers, at <a href="{APP}">{SITE}{APP}</a>.</li>
        <li>Short dramas, series and movies with free first episodes, published by creators themselves, and a feed of creator videos, photos and posts.</li>
        <li>AI tools for creators, led by the AI Repurposer, which turns long videos into short clips.</li>
        <li>Viyo Coins, earned in the app or bought, for AI tools, drama episodes and boosts.</li>
      </ul>

      <h2>How Viyo treats your content</h2>
      <ul class="plain">
        <li>Viyo does not sell your content or conversations and does not use your photos or videos to train AI models.</li>
        <li>When you use an AI tool, what you send to it is processed by OpenAI to produce the result.</li>
        <li>You can delete your account and its data from Settings.</li>
      </ul>

      <h2>Contact</h2>
      <p>Questions, feedback or partnership ideas: <a href="/contact">get in touch</a>.</p>
    </section>
    {cta()}
"""
    return page("/about", "About Viyo: A Creator-Focused Video Platform",
                "Viyo is a creator-focused video platform for short drama series and creator videos, with AI tools "
                "that turn long videos into short clips.",
                body, schema=[ORG, APPLICATION], crumbs=[("/about", "About")], og_type="website")


def faq() -> str:
    items = "".join(f"<details><summary>{e(q)}</summary><p>{e(a)}</p></details>" for q, a in FAQ)
    schema = {"@type": "FAQPage", "mainEntity": [
        {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in FAQ]}
    body = f"""
    <section class="wrap prose">
      <p class="eyebrow">FAQ</p>
      <h1>Frequently asked questions</h1>
      <div class="faq">{items}</div>
    </section>
    {cta()}
"""
    return page("/faq", "Viyo FAQ: Pricing, AI Clips, Short Dramas and Privacy",
                "Answers about Viyo: pricing, how the AI Repurposer turns long videos into shorts, clip lengths, "
                "short drama episodes, coins and privacy.",
                body, schema=[schema], crumbs=[("/faq", "FAQ")])


def contact() -> str:
    body = f"""
    <section class="wrap prose">
      <p class="eyebrow">Contact</p>
      <h1>Contact Viyo</h1>
      <p class="lead">Email <a href="mailto:{CONTACT_EMAIL}">{CONTACT_EMAIL}</a>.</p>
      <ul class="plain">
        <li><strong>Help with the app:</strong> tell us what you were doing and what happened. A screenshot helps.</li>
        <li><strong>Copyright:</strong> include a link to the content and proof that you own the rights.</li>
        <li><strong>Payments:</strong> include the email on your Viyo account and the date of the purchase.</li>
        <li><strong>Deleting your account:</strong> you can do it yourself in the app under Settings.</li>
      </ul>
    </section>
    {cta()}
"""
    schema = {"@type": "ContactPage", "url": f"{SITE}/contact", "mainEntity": {"@id": f"{SITE}/#organization"}}
    return page("/contact", "Contact Viyo",
                "How to contact Viyo for help with the app, copyright concerns, payments or partnerships.",
                body, schema=[ORG, schema], crumbs=[("/contact", "Contact")])


PAGES = {
    "/": ("index.html", home, "1.0", "weekly"),
    "/features": ("features.html", features, "0.9", "weekly"),
    "/creators": ("creators.html", creators, "0.8", "monthly"),
    "/ai-video-to-shorts": ("ai-video-to-shorts.html", ai_shorts, "0.9", "monthly"),
    "/short-drama": ("short-drama.html", short_drama, "0.8", "monthly"),
    "/publish": ("publish.html", publish, "0.9", "monthly"),
    "/faq": ("faq.html", faq, "0.7", "monthly"),
    "/about": ("about.html", about, "0.6", "monthly"),
    "/contact": ("contact.html", contact, "0.4", "yearly"),
}


def sitemap() -> str:
    urls = "".join(
        f"  <url><loc>{SITE}{p if p != '/' else '/'}</loc><lastmod>{UPDATED}</lastmod>"
        f"<changefreq>{cf}</changefreq><priority>{pr}</priority></url>\n"
        for p, (_, _, pr, cf) in PAGES.items())
    return f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{urls}</urlset>\n'


def robots() -> str:
    return f"""# Viyo public pages are open to search engines and AI search crawlers.
# /app/ is the signed-in web app; its shell carries a noindex tag rather
# than a block here, so crawlers can see that tag.

User-agent: Googlebot
Allow: /

User-agent: Bingbot
Allow: /

User-agent: OAI-SearchBot
Allow: /

User-agent: *
Allow: /

Sitemap: {SITE}/sitemap.xml
"""


def llms() -> str:
    lines = "\n".join(f"- [{n}]({SITE}{p}): {d}" for p, n, d in [
        ("/", "Home", "What Viyo is and who it is for"),
        ("/features", "Features", "Every available feature with prices, and what is not available yet"),
        ("/ai-video-to-shorts", "AI video to shorts", "How the AI Repurposer turns long videos into short clips"),
        ("/creators", "For creators", "Posting, short drama publishing and AI tools for creators"),
        ("/short-drama", "Short dramas", "Watching short drama series; first 3 episodes free"),
        ("/publish", "Publish your film", "How creators publish their own dramas, series and movies and earn coins"),
        ("/faq", "FAQ", "Pricing, limits, privacy and common questions"),
        ("/about", "About", "About Viyo and how it treats user content"),
        ("/contact", "Contact", "How to reach Viyo"),
    ])
    return f"""# Viyo

> {DESCRIPTION}

Viyo runs in the web browser at {SITE}{APP}. It is free to join. Some AI tools and later drama episodes use Viyo Coins (earned in the app or bought in packs from $0.99); Viyo Premium is an optional subscription for unlimited drama episodes.

Key facts:
- AI Repurposer: upload a video up to about 30 minutes; get up to 6 vertical 9:16 clips (about 12-60 seconds) with burned-in captions and a hook line. Clip length can be Auto, Short (15-30 s, 40 at most), Medium (30-45 s, 55 at most) or Long (45-60 s). First video free (up to 10 minutes), then 40 coins; coins are refunded if no clip is good enough.
- Short dramas: series in short episodes; the first 3 episodes of every series are free.
- Publishing: creators upload their own short dramas, series, movies, short films and AI films, set the coin price, and keep 65% of the coins viewers spend unlocking them (only bought coins count; each earned coin is worth $0.006; withdraw from $10 to PayPal or mobile money, sent by the Viyo team).
- Other AI tools: Hook Check, Caption Ideas, Improve with AI, Why This Worked, Voice Consistency Check, AI Video Coach, weekly report, Glow Up (18+).
- Not available yet: Glow Up hairstyle image previews.

## Pages

{lines}
"""


def main() -> None:
    os.makedirs(os.path.join(OUT, "assets"), exist_ok=True)
    for path, (fname, fn, _, _) in PAGES.items():
        with open(os.path.join(OUT, fname), "w", encoding="utf-8") as f:
            f.write(fn())
    # app-ads.txt: authorises Google AdMob to sell ads in the Viyo app
    # (publisher id from the app's AdMob app id, Google's standard cert id).
    app_ads = "google.com, pub-4006935524883605, DIRECT, f08c47fec0942fa0\n"
    for name, text in [("sitemap.xml", sitemap()), ("robots.txt", robots()), ("llms.txt", llms()),
                       ("app-ads.txt", app_ads)]:
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
            f.write(text)
    print(f"wrote {len(PAGES)} pages + sitemap.xml, robots.txt, llms.txt, app-ads.txt to {OUT}")


if __name__ == "__main__":
    main()
