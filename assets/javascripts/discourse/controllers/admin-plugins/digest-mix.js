import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class AdminPluginsDigestMixController extends Controller {
  @tracked activeTab = "emailMix";
  @tracked saving = false;
  @tracked saveSuccess = false;

  tabs = [
    { id: "emailMix",       label: "Email Mix" },
    { id: "contentMix",     label: "Content Mix" },
    { id: "firstTopic",     label: "First Topic" },
    { id: "freshness",      label: "Freshness" },
    { id: "cooldowns",      label: "Cooldowns" },
    { id: "productWeights", label: "Product Weights" },
    { id: "topicTypes",     label: "Topic Types" },
  ];

  get settings() {
    return this.model.settings;
  }

  get activeProducts() {
    return this.model.activeProducts;
  }

  get registry() {
    try {
      return JSON.parse(this.settings.digest_mix_topic_type_registry || "[]");
    } catch {
      return [];
    }
  }

  get emailTypeSplit() {
    try {
      return JSON.parse(this.settings.digest_mix_email_type_split || "{}");
    } catch {
      return { regular: 70, push: 20, auto_campaign: 10 };
    }
  }

  get topicTypeSplit() {
    try {
      return JSON.parse(this.settings.digest_mix_topic_type_split || "{}");
    } catch {
      return {};
    }
  }

  get firstTopicSplit() {
    try {
      return JSON.parse(this.settings.digest_mix_first_topic_split || "{}");
    } catch {
      return {};
    }
  }

  get freshnessConfig() {
    try {
      return JSON.parse(this.settings.digest_mix_freshness_config || "{}");
    } catch {
      return {};
    }
  }

  get productWeights() {
    try {
      return JSON.parse(this.settings.digest_mix_product_weights || "{}");
    } catch {
      return {};
    }
  }

  @action
  selectTab(tabId) {
    this.activeTab = tabId;
  }

  @action
  updateEmailTypeSplit(newSplit) {
    this.settings.digest_mix_email_type_split = JSON.stringify(newSplit);
  }

  @action
  updateTopicTypeSplit(newSplit) {
    this.settings.digest_mix_topic_type_split = JSON.stringify(newSplit);
  }

  @action
  updateFirstTopicSplit(newSplit) {
    this.settings.digest_mix_first_topic_split = JSON.stringify(newSplit);
  }

  @action
  updateFreshnessConfig(typeId, field, value) {
    const cfg = this.freshnessConfig;
    cfg[typeId] = cfg[typeId] || {};
    cfg[typeId][field] = value;
    this.settings.digest_mix_freshness_config = JSON.stringify(cfg);
  }

  @action
  updateProductWeight(typeId, productName, weight) {
    const weights = this.productWeights;
    weights[typeId] = weights[typeId] || {};
    weights[typeId][productName] = parseFloat(weight) || 0;
    this.settings.digest_mix_product_weights = JSON.stringify(weights);
  }

  @action
  boostProduct(typeId, productName) {
    const weights = this.productWeights;
    const current = (weights[typeId] || {})[productName] ?? 1;
    this.updateProductWeight(typeId, productName, current * 2);
  }

  @action
  pauseProduct(typeId, productName) {
    this.updateProductWeight(typeId, productName, 0);
  }

  @action
  updateRegistry(newRegistry) {
    this.settings.digest_mix_topic_type_registry = JSON.stringify(newRegistry);
  }

  @action
  async save() {
    this.saving = true;
    this.saveSuccess = false;
    try {
      await ajax("/admin/digest-mix/settings.json", {
        type: "POST",
        data: this.settings,
      });
      this.saveSuccess = true;
      setTimeout(() => (this.saveSuccess = false), 3000);
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.saving = false;
    }
  }
}
