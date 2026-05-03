import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";

export default class DigestMixProductWeights extends Component {
  // args:
  //   typeId        — string
  //   typeLabel     — string
  //   typeColor     — string
  //   activeProducts — array of { id, name }
  //   weights       — object { productName: weight }
  //   onUpdate      — action(typeId, productName, weight)
  //   onBoost       — action(typeId, productName)
  //   onPause       — action(typeId, productName)

  @tracked expanded = false;

  get productsWithWeights() {
    const weights   = this.args.weights || {};
    const products  = this.args.activeProducts || [];
    const total     = products.reduce((s, p) => s + (parseFloat(weights[p.name] ?? 1) || 0), 0);

    return products.map((p) => {
      const w = parseFloat(weights[p.name] ?? 1) || 0;
      return {
        name:    p.name,
        weight:  w,
        percent: total > 0 ? ((w / total) * 100).toFixed(1) : "0.0",
        paused:  w <= 0,
      };
    });
  }

  @action
  toggleExpanded() {
    this.expanded = !this.expanded;
  }

  @action
  onWeightInput(productName, event) {
    this.args.onUpdate?.(this.args.typeId, productName, event.target.value);
  }

  @action
  boost(productName) {
    this.args.onBoost?.(this.args.typeId, productName);
  }

  @action
  pause(productName) {
    this.args.onPause?.(this.args.typeId, productName);
  }
}
