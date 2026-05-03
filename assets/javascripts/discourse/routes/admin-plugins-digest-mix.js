import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsDigestMixRoute extends Route {
  async model() {
    const [settingsResp, productsResp] = await Promise.all([
      ajax("/digest-mix/settings"),
      ajax("/digest-mix/active_products"),
    ]);
    return {
      settings: settingsResp,
      activeProducts: productsResp.products || [],
    };
  }
}
