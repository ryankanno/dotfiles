// ~/.finicky.js

const regex = /^https?:\/\/twitter\.com\/(?:#!\/)?(\w+)\/status(?:es)?\/(\d+).*$/

module.exports = {
  defaultBrowser: "Firefox",
  rewrite: [
    {
      match: ({urlString, opener}) => {
        const matches = urlString.match(regex);
        return matches && matches[2] && opener.bundleId !== "com.tapbots.Tweetbot3Mac";
      },
      url: ({ urlString }) => {
        const [_, user, statusId] = urlString.match(regex);
        return `tweetbot://${user}/status/${statusId}`;
      }
    }
  ],
  handlers: [
    {
      match: ({ url }) => url.protocol === "tweetbot",
      browser: "com.tapbots.Tweetbot3Mac"
    },
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
