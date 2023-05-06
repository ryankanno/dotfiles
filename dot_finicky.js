// ~/.finicky.js

module.exports = {
  defaultBrowser: "Firefox",
  handlers: [
    {
      match: "open.spotify.com/*",
      browser: "Spotify"
    },
    {
      match: finicky.matchHostnames(["meet.jit.si", "meet.google.com", "hangouts.google.com"]),
      browser: "Google Chrome"
    },
    {
      match: [
        "zoom.us/*",
        finicky.matchDomains(/.*\zoom.us/),
        /zoom.us\/j\//,
      ],
      browser: "us.zoom.xos"
    }
  ]
};
