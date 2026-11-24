# encoding: UTF-8
# Leitura da planilha de armaduras (CSV) e cálculo do resumo de aço.
# Ruby puro: não depende da API do SketchUp.
#
# Uma linha por posição (ou por trecho de estribos), separador ";":
#   PEÇA;POS;BITOLA;QTD;COMP;TIPO;INÍCIO;FIM;ESPAC;FORMA
#   PPF1;N1;16;2;886;L;0;866;;
#   PPF1;N5;5;48;164;E;150;866;15;20x45
#
#   PEÇA    nome da peça no modelo (ex.: PPF1)
#   POS     posição (N1, N2...)
#   BITOLA  diâmetro em mm (12,5)
#   QTD     quantidade por peça (estribos: vazio = calculado pelo trecho)
#   COMP    comprimento de corte da barra, cm (C=)
#   TIPO    L = longitudinal, E = estribo (vazio: E se tiver ESPAC)
#   INÍCIO  início do trecho ao longo da peça, cm (vazio = 0)
#   FIM     fim do trecho, cm (longitudinal vazio = INÍCIO + COMP)
#   ESPAC   espaçamento dos estribos, cm
#   FORMA   estribo: largura x altura internas em cm (ex.: 20x45)
#
# A mesma posição pode aparecer em mais de uma linha (estribos em trechos
# com espaçamentos diferentes); no resumo as quantidades são somadas.
module DetalhamentoPM
  module Armadura
    module_function

    MASSA_ACO = 7850.0   # kg/m³ (NBR 7480)

    COLUNAS = {
      'PEC' => :peca, 'POS' => :pos, 'BIT' => :bitola, 'DIAM' => :bitola,
      'QT' => :qtd, 'QUANT' => :qtd,
      'COMP' => :comp, 'TIP' => :tipo, 'INI' => :ini, 'FIM' => :fim,
      'ESP' => :espac, 'FORM' => :forma
    }.freeze

    # Texto em UTF-8 válido, venha na codificação que vier.
    def utf8(s)
      t = s.to_s
      return t if t.encoding == Encoding::UTF_8 && t.valid_encoding?
      u = t.dup.force_encoding('UTF-8')
      return u if u.valid_encoding? && (t.encoding == Encoding::BINARY || t.ascii_only?)
      t.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end

    def sem_acento(s)
      utf8(s).unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
    end

    def chave_peca(nome)
      sem_acento(nome).upcase.strip.gsub(/\s+/, ' ')
    end

    # Lê o arquivo aceitando UTF-8 (com ou sem BOM) ou Windows-1252
    # (o "CSV separado por ponto e vírgula" do Excel em português).
    def ler_arquivo(caminho)
      bruto = File.binread(caminho)
      txt = bruto.dup.force_encoding('UTF-8')
      unless txt.valid_encoding?
        txt = bruto.dup.force_encoding('Windows-1252').encode('UTF-8')
      end
      ler(txt)
    end

    def numero(s)
      t = s.to_s.strip.delete('"').tr(',', '.')
      return nil if t.empty?
      Float(t)
    rescue ArgumentError
      :invalido
    end

    def campos(linha)
      sep = linha.include?(';') ? ';' : (linha.include?("\t") ? "\t" : ',')
      linha.split(sep, -1).map { |c| c.strip.sub(/\A"(.*)"\z/, '\1').strip }
    end

    # Devolve [dados, erros]. dados = { 'PPF1' => [item, ...] } (chave em
    # maiúsculas, sem acento). item = { peca:, pos:, bitola:, qtd:, comp:,
    # tipo: 'L'|'E', ini:, fim:, espac:, forma: [b, h] ou nil, linha: }.
    def ler(texto)
      linhas = utf8(texto).sub(/\A﻿/, '').split(/\r?\n/)
      erros = []
      dados = Hash.new { |h, k| h[k] = [] }
      cab = nil
      linhas.each_with_index do |ln, i|
        nl = i + 1
        next if ln.strip.empty? || ln.strip.start_with?('#')
        cs = campos(ln)
        next if cs.all?(&:empty?)
        unless cab
          cab = cs.map do |c|
            n = sem_acento(c).upcase.gsub(/[^A-Z]/, '')
            COLUNAS.find { |pre, _| n.start_with?(pre) }&.last
          end
          faltam = %i[peca pos bitola comp] - cab
          unless faltam.empty?
            erros << "linha #{nl}: cabeçalho sem as colunas #{faltam.map { |f| f.to_s.upcase }.join(', ')}"
            return [{}, erros]
          end
          next
        end
        v = {}
        cab.each_with_index { |campo, k| v[campo] = cs[k].to_s if campo }
        item, erro = montar(v, nl)
        if erro
          erros << erro
        else
          dados[chave_peca(item[:peca])] << item
        end
      end
      erros << 'planilha sem cabeçalho' unless cab
      [Hash[dados], erros]
    end

    def montar(v, nl)
      peca = v[:peca].to_s.strip
      pos = v[:pos].to_s.strip.upcase
      return [nil, "linha #{nl}: falta a peça"] if peca.empty?
      return [nil, "linha #{nl}: falta a posição"] if pos.empty?
      nums = {}
      %i[bitola qtd comp ini fim espac].each do |k|
        n = numero(v[k])
        return [nil, "linha #{nl}: #{k.to_s.upcase} inválido (#{v[k]})"] if n == :invalido
        nums[k] = n
      end
      return [nil, "linha #{nl}: #{pos} sem bitola"] unless nums[:bitola] && nums[:bitola] > 0
      return [nil, "linha #{nl}: #{pos} sem comprimento"] unless nums[:comp] && nums[:comp] > 0
      tipo = v[:tipo].to_s.strip.upcase[0]
      tipo = nums[:espac] ? 'E' : 'L' if tipo.nil? || tipo.empty?
      return [nil, "linha #{nl}: TIPO deve ser L ou E (#{v[:tipo]})"] unless %w[L E].include?(tipo)
      ini = nums[:ini] || 0.0
      forma = nil
      if (m = v[:forma].to_s.tr(',', '.').match(/([\d.]+)\s*[xX×*]\s*([\d.]+)/))
        forma = [m[1].to_f, m[2].to_f]
      end
      if tipo == 'E'
        fim = nums[:fim]
        return [nil, "linha #{nl}: estribo #{pos} sem FIM do trecho"] unless fim
        return [nil, "linha #{nl}: estribo #{pos} com FIM antes do INÍCIO"] if fim < ini
        qtd = nums[:qtd]
        unless qtd
          return [nil, "linha #{nl}: estribo #{pos} sem QTD nem ESPAC"] unless nums[:espac] && nums[:espac] > 0
          qtd = ((fim - ini) / nums[:espac]).floor + 1
        end
      else
        fim = nums[:fim] || ini + nums[:comp]
        qtd = nums[:qtd]
        return [nil, "linha #{nl}: #{pos} sem quantidade"] unless qtd
        return [nil, "linha #{nl}: #{pos} com FIM antes do INÍCIO"] if fim < ini
      end
      [{ peca: peca, pos: pos, bitola: nums[:bitola], qtd: qtd.round, comp: nums[:comp],
         tipo: tipo, ini: ini, fim: fim, espac: nums[:espac], forma: forma, linha: nl }, nil]
    end

    # Massa linear da barra (kg/m).
    def massa_linear(bitola_mm, massa_aco = MASSA_ACO)
      Math::PI / 4.0 * (bitola_mm / 1000.0)**2 * massa_aco
    end

    def ordem_pos(pos)
      n = pos.to_s[/\d+/]
      [n ? n.to_i : 9999, pos.to_s]
    end

    # Resumo de aço por posição: [{ pos:, bitola:, qtd:, comp:, peso_unit:,
    # peso_total: }], ordenado por N1, N2... e o peso total (kg).
    def resumo(itens, massa_aco = MASSA_ACO)
      grupos = {}
      itens.each do |it|
        g = grupos[it[:pos]] ||= { pos: it[:pos], bitola: it[:bitola], qtd: 0, comp: it[:comp] }
        g[:qtd] += it[:qtd]
      end
      linhas = grupos.values.sort_by { |g| ordem_pos(g[:pos]) }
      linhas.each do |g|
        g[:peso_unit] = massa_linear(g[:bitola], massa_aco) * g[:comp] / 100.0
        g[:peso_total] = g[:peso_unit] * g[:qtd]
      end
      [linhas, linhas.inject(0.0) { |s, g| s + g[:peso_total] }]
    end

    # Avisos de coerência (posição repetida com bitola ou comprimento diferente).
    def avisos(itens)
      res = []
      itens.group_by { |it| it[:pos] }.each do |pos, its|
        res << "#{its.first[:peca]} #{pos}: bitolas diferentes" if its.map { |i| i[:bitola] }.uniq.size > 1
        res << "#{its.first[:peca]} #{pos}: comprimentos diferentes" if its.map { |i| i[:comp] }.uniq.size > 1
      end
      res
    end

    def fmt_bitola(b)
      format('%.1f', b).tr('.', ',')
    end
  end
end
