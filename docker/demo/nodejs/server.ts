const server = Bun.serve({
  hostname: "0.0.0.0",
  port: 3000,
  fetch(request) {
    return new Response("Welcome to bun");
  }
})

console.log(`Listening on ${server.url}`);
