// ~/.finicky.js

const regex = /^https?:\/\/twitter\.com\/(?:#!\/)?(\w+)\/status(?:es)?\/(\d+).*$/

module.exports = {
  defaultBrowser: "Firefox",
  rewrite: [
    {
      match: ({urlString}) => {
        const matches = urlString.match(regex);
        finicky.log(JSON.stringify(matches, null, 2))
        return matches && matches[2];
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
  ]
};
