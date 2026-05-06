import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

console.log("[digest-mix] route file loaded");

export default class AdminPluginsDigestMixRoute extends Route {
  beforeModel(transition) {
    console.log("[digest-mix] beforeModel called — transition to:", transition?.targetName);
  }

  async model() {
    console.log("[digest-mix] model() called — fetching settings + products");
    try {
      const [settingsResp, productsResp] = await Promise.all([
        ajax("/admin/digest-mix/settings.json"),
        ajax("/admin/digest-mix/active_products.json"),
      ]);
      console.log("[digest-mix] model() success — settings:", settingsResp, "products:", productsResp);
      return {
        settings: settingsResp,
        activeProducts: productsResp.products || [],
      };
    } catch (e) {
      console.error("[digest-mix] model() FAILED:", e);
      throw e;
    }
  }
}
