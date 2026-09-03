# Analisador de Hints & Warnings para Lazarus IDE (OTA)

Extensão nativa (pacote IDE) para o **Lazarus IDE** (inspirado nos plug-ins OTA do Delphi) para monitoramento passivo do ciclo de compilação do Free Pascal Compiler (FPC), integração nativa com banco de dados **Firebird 5.0** contendo o catálogo oficial de diagnósticos, e assistência inteligente para correção de código via **Ollama (IA local offline)** e **Google Gemini (IA em nuvem)** com aplicação de Quick Fix diretamente no editor de código.

---

## 🚀 Principais Recursos

- **Monitoramento Passivo do Ciclo de Build:** Intercepta automaticamente alertas, notas, avisos e erros assim que a compilação do projeto termina (`AddHandlerOnProjectBuildingFinished`).
- **Base de Dados Firebird 5.0 Integrada:** Catálogo completo com mais de 900 diagnósticos oficiais do FPC (Hints, Notes, Warnings, Errors e Fatal Errors) com explicações em Português, causas prováveis e roteiros de correção.
- **Quick Fix Nativo com CodeTools e Editor:** Refatoração de código automática com suporte a `Ctrl + Z` (desfazer) para:
  - Remoção de units não utilizadas na cláusula `uses` (`Code 5025`).
  - Injeção de diretiva de supressão `{%H-}` em parâmetros não utilizados (`Code 5023`).
  - Remoção de variáveis locais não utilizadas (`Code 5024`).
  - Substituição de typecasts incompatíveis de 64-bit (`PtrInt`/`PtrUInt`) (`Code 4055/4056`).
- **Diagnóstico Inteligente com IA Local (Ollama):**
  - Execução assíncrona em segundo plano sem congelar a interface gráfica da IDE.
  - Análise contextual das linhas do código-fonte ao redor do erro.
  - Suporte a modelos como `qwen2.5-coder:3b`, `starcoder2:3b`, `llama3.2:1b`, etc.
- **Diagnóstico com Google Gemini:**
  - Suporte ao Gemini CLI oficial (`@google/gemini-cli`) e API do Google Gemini (`gemini-2.0-flash` / `gemini-1.5-flash`).
  - Análise profunda de erros complexos, portabilidade Windows ➔ Linux e sugestões prontas.
- **Aplicação Automática de Código Sugerido pela IA:**
  - Botão **"⚡ Aplicar este Código no Editor"** para substituir a linha problemática pela sugestão da IA.
  - Comenta a linha original para segurança e aplica a indentação correta.
  - Injeta automaticamente units dependentes (ex: `LCLIntf` para `OpenURL`) via CodeTools.
- **Interface Gráfica Moderna (LCL):**
  - Painel de métricas rápidas (Total, Warnings, Hints, Notes, Erros).
  - Agrupamento por arquivo ou visão linear.
  - Abas dedicadas: *💡 Catálogo Firebird 5.0* e *🤖 Solução com IA*.
  - Exportação de relatórios em **CSV** e **JSON**.
  - Captura e categorização de avisos globais de projeto e pacotes sob `Projeto / Opções Globais`.

---

## 📂 Estrutura do Projeto

```
├── LazarusHintsWarnings.lpk      # Arquivo de pacote do Lazarus (Lazarus Package)
├── LazarusHintsWarnings.pas      # Unit principal do pacote
├── UHintsWarnings.Config.pas     # Gerenciamento de configurações (.ini)
├── UHintsWarnings.Database.pas   # Conexão nativa com Firebird 5.0 (SQLdb)
├── UHintsWarnings.Gemini.pas     # Integração com Gemini CLI / Google AI
├── UHintsWarnings.Model.pas      # Modelo de dados e parser de mensagens FPC
├── UHintsWarnings.Ollama.pas     # Integração com servidor local Ollama
├── UHintsWarnings.QuickFix.pas   # Motor de refatoração CodeTools / SrcEditorIntf
├── UHintsWarnings.Register.pas   # Registro do plugin e listeners na IDE
├── UHintsWarnings.View.lfm       # Formulário da interface gráfica (LCL)
├── UHintsWarnings.View.pas       # Lógica da interface e inspetor
├── database/
│   ├── schema.sql                # DDL do Firebird 5.0 (Tabelas, índices, triggers)
│   ├── insert_all_fpc_messages.sql # Carga dos 944 diagnósticos oficiais do FPC
│   ├── build_all_messages_sql.py # Script de extração a partir dos fontes do FPC
│   └── queries.sql               # Consultas analíticas de exemplo
└── README.md
```

---

## 🛠️ Instalação no Lazarus

1. Abra o Lazarus IDE.
2. Acesse o menu **Pacote ➔ Abrir Arquivo de Pacote (.lpk)...**.
3. Selecione o arquivo `LazarusHintsWarnings.lpk`.
4. No Editor de Pacotes, clique em **Compilar** e depois em **Usar ➔ Instalar**.
5. O Lazarus solicitará a recompilação da IDE. Confirme e aguarde o reinício da IDE.
6. A extensão estará disponível no menu **Ferramentas ➔ Analisador de Hints & Warnings**.

---

## 🗄️ Configuração do Banco Firebird 5.0

Para criar a base de dados de diagnósticos:

```bash
# Executar o DDL de criação e tabelas
isql -u SYSDBA -p masterkey -i database/schema.sql

# Inserir o catálogo completo de 944 mensagens FPC
isql -u SYSDBA -p masterkey 127.0.0.1:/caminho/fpc_diagnostics.fdb -i database/insert_all_fpc_messages.sql
```

No Analisador dentro do Lazarus, clique em **Configurações...** e informe o Host (`127.0.0.1`), Porta (`3050`) e o caminho absoluto do arquivo `.fdb`.

---

## 🤖 Configuração de Inteligência Artificial

### Ollama (Local / Offline)
1. Instale o Ollama e baixe o modelo desejado:
   ```bash
   ollama pull qwen2.5-coder:3b
   ```
2. O plug-in conecta-se automaticamente em `http://localhost:11434`.

### Google Gemini (Nuvem)
1. Obtenha uma chave de API gratuita no [Google AI Studio](https://aistudio.google.com/).
2. Clique em **Configurações...** na janela do Analisador e informe sua chave no campo `GEMINI_API_KEY`, ou exporte no seu ambiente Linux:
   ```bash
   export GEMINI_API_KEY="sua-chave-aqui"
   ```

---

## 📄 Licença

Este projeto é distribuído sob a licença **MIT**.
