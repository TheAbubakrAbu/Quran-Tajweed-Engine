# 24 · The chains of transmission

The isnād of each of the Ten Readings: from the Prophet ﷺ down through the Companions who learned from him, the Successors who taught each imam, the imam himself, the links between him and each of his two narrators, and the students who carried each narration on.

> **Key fact:** ask the corpus which imam a riwayah comes from. **Do not parse the tag.** Four tags name the imam in the Arabic genitive (`"ad-Duri an Abi Amr"`) while his key is the nominative (`"Abu Amr"`), so splitting on `" an "` resolves those four to nothing.

## A chain, as layers

```js
engine.isnad.chain("Warsh an Nafi").map((l) => l.title);
// ["THE PROPHET", "THE COMPANIONS", "HIS TEACHERS", "THE IMAM", "THE NARRATOR", "HIS STUDENTS"]
```

Layers come back top to bottom, one per generation, which is how a diagram draws it: a row per layer, connected downward. Each layer is `{ title, nodes }`, and each node is `{ name, arabic, detail, role }`, where `detail` is the death year (`"d. 117 AH"`) and `role` is one of `prophet`, `companion`, `successor`, `imam`, `link`, `narrator`, `student`.

Pass an **imam key** instead and you get the reading's own chain, which ends at his two narrators rather than following one of them down:

```js
engine.isnad.chain("Nafi").map((l) => l.title);
// ["THE PROPHET", "THE COMPANIONS", "HIS TEACHERS", "THE IMAM", "HIS TWO NARRATORS"]
```

An unknown key returns an empty array rather than throwing.

## Which imam

```js
engine.isnad.imamOf("Warsh an Nafi");      // "Nafi"
engine.isnad.imamOf("ad-Duri an Abi Amr"); // "Abu Amr"  ← not "Abi Amr"
```

This reads the imam the corpus records for that narration. The tags are display names and their grammar varies; the mapping does not.

## Reading directly, or through links

```js
engine.isnad.readsDirectly("Hafs an Asim");          // true
engine.isnad.readsDirectly("Qunbul an Ibn Kathir");  // false — three links between
engine.isnad.sentence("Qunbul an Ibn Kathir");
// "Qunbul did not meet Ibn Kathir: the reading reached him through Ahmad al-Qawwas,
//  Abu al-Ikhrit Wahb ibn Wadih and then Isma'il al-Qust, and from Ibn Kathir it runs
//  through his teachers to the Companions and to the Prophet ﷺ."
```

`readsDirectly` is exactly "has no links between", and `sentence` says which of the two it is in prose, for a caption under a diagram.

## Abu Jafar has no teachers, and that is correct

Every imam reaches Companions, but **Abu Jafar reaches them directly**: he was himself a Successor, who read on Ibn Abbas and Abu Hurayrah. So his chain has no `HIS TEACHERS` layer, and a chain is four layers rather than five. Do not treat an empty `teachers` list as missing data.

## Counts

| | |
|---|---|
| Imams | 10 |
| Narrators | 20 (exactly two per imam) |
| Companions | 13 |

## Sourcing

The links are the standard ones of the classical record: Ibn al-Jazarī's *al-Nashr* and *Ghāyat al-Nihāyah*, al-Dānī's *al-Taysīr*, and the ṭuruq of al-Shāṭibiyyah and al-Durrah, kept consistent with the death years this engine already ships. Where a narrator's students are not listed with confidence, the layer is simply left out rather than filled in.
