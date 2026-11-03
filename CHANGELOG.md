# Histórico de versões

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e as versões seguem o [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [0.3.1] - 2026-11-02
### Alterado
- Projeto renomeado para **A3-Detailer**: nome no Gerenciador de extensões,
  menu do SketchUp, README e arquivo `.rbz` (`A3-Detailer-<versão>.rbz`).
- O nome interno (pasta `detalhamento_pm` e módulo `DetalhamentoPM`) foi mantido,
  para que quem já instalou a versão anterior atualize sem duplicar a extensão.

## [0.3.0] - 2026-11-02
### Adicionado
- Saída em **PDF vetorial A3** gerada pelo próprio plugin (sem AutoCAD).
- Opção de formato: PDF por peça, PDF único (uma prancha por página), PDF e DXF, ou só DXF.
- Estilos de impressão por camada (espessura, cor e tracejado).
- Testes automatizados e simulação da API do SketchUp para rodar fora do programa.

## [0.2.0] - 2026-11-02
### Adicionado
- Prancha **A3 de formas** por tipo de peça, em DXF (NBR 16752).
- Vista superior e vista lateral com **linhas ocultas** tracejadas e escala automática.
- **Cortes automáticos** nos trechos onde a seção muda, com hachura e cotas.
- Cotas em cadeia e totais, posição de insertos (alças, chapas) e marcas de corte.
- Modelo 3D isométrico, quadro resumo (dimensões, volume, peso, fck), revisões e carimbo.
- Nome de arquivo no padrão `PREFIXO-OBRA-DET-PEÇA-Rxx`.
### Removido
- Detalhamento desenhado dentro do modelo do SketchUp (substituído pelas pranchas).

## [0.1.0] - 2026-11-02
### Adicionado
- Primeira versão: vistas 2D cotadas (superior, frontal e lateral) desenhadas
  ao lado do modelo, agrupando peças iguais.
- Filtro por tags e exportação da lista de peças em CSV.
