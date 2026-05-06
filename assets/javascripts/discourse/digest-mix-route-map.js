console.log("[digest-mix] route-map.js loaded");

export default {
  resource: "admin.adminPlugins",
  path: "/plugins",

  map() {
    console.log("[digest-mix] route-map.map() called — registering digest-mix route");
    this.route("digest-mix", { path: "digest-mix" });
  },
};
