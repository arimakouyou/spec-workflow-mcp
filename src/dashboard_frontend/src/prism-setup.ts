// @lexical/code が読み込む prismjs の言語定義(prismjs/components/prism-*)は
// グローバル Prism の存在を前提とする。バンドル後の評価順によっては言語定義が
// core より先に実行され「Prism is not defined」でアプリ全体が起動不能になるため、
// エントリ最先頭で core を評価しグローバルを確立する。
import Prism from 'prismjs';

(globalThis as unknown as { Prism: typeof Prism }).Prism = Prism;
