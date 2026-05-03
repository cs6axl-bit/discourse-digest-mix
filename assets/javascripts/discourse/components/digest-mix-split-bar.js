import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";

export default class DigestMixSplitBar extends Component {
  // args:
  //   split        — object { key: value, ... } (values are weights/percents)
  //   colors       — optional object { key: "#hex" }
  //   labels       — optional object { key: "Label" }
  //   onChange     — action(newSplit)

  get normalizedSegments() {
    const split  = this.args.split || {};
    const colors = this.args.colors || {};
    const labels = this.args.labels || {};
    const total  = Object.values(split).reduce((s, v) => s + parseFloat(v || 0), 0);
    if (total === 0) return [];

    return Object.entries(split).map(([key, value]) => ({
      key,
      value:   parseFloat(value || 0),
      percent: ((parseFloat(value || 0) / total) * 100).toFixed(1),
      color:   colors[key] || "#888",
      label:   labels[key] || key,
    }));
  }

  @action
  onInput(key, event) {
    const raw    = parseFloat(event.target.value) || 0;
    const split  = { ...this.args.split };
    split[key]   = raw;
    this.args.onChange?.(split);
  }
}
