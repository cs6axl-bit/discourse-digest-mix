import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsDigestMixRoute extends Route {
  async model() {
    const [settingsResp, productsResp] = await Promise.all([
      ajax("/admin/digest-mix/settings.json"),
      ajax("/admin/digest-mix/active_products.json"),
    ]);
    return {
      settings: settingsResp,
      activeProducts: productsResp.products || [],
    };
  }
}
