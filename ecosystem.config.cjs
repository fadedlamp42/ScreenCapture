// pm2 ecosystem config for ScreenCapture
// usage: pm2 start ecosystem.config.cjs

module.exports = {
  apps: [
    {
      name: "screencapture",
      script: "make",
      args: "run",
      cwd: __dirname,
      interpreter: "none",

      // auto-restart on crash; rebuild is fast when binary is up-to-date
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      restart_delay: 3000,

      watch: false,

      // logging
      log_date_format: "YYYY-MM-DD HH:mm:ss",
      merge_logs: true,

      // graceful shutdown
      kill_timeout: 5000,
    },
  ],
};
