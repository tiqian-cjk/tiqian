// Zero-config entry (wc-s5 scope item 2). Importing this module registers
// <tiqian-prose> with the default options, restoring the historical
// one-line setup. Consumers who need parameterized registration import
// registerTiqianProse from @tiqian/web-component/element and call it themselves.
import { registerTiqianProse } from "./element.js";

registerTiqianProse();
