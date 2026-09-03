#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script para extrair todos os Hints, Warnings, Notes e Erros oficiais do FPC
(a partir de errore.msg e errorptu.msg) e gerar o script SQL para o Firebird 5.0.
"""

import re
import os

EN_PATH = '/usr/share/fpcsrc/3.2.2/compiler/msg/errore.msg'
PT_PATH = '/usr/share/fpcsrc/3.2.2/compiler/msg/errorptu.msg'
OUT_SQL = '/home/mauricio/Projetos Antigravity/OTa Lazarus/database/insert_all_fpc_messages.sql'

def clean_latex(text):
    text = re.sub(r'\\var\{([^}]+)\}', r"'\1'", text)
    text = re.sub(r'\\seeo\{([^}]+)\}', r'\1', text)
    text = re.sub(r'\\item\s*', '• ', text)
    text = re.sub(r'\\begin\{[^}]+\}', '', text)
    text = re.sub(r'\\end\{[^}]+\}', '', text)
    text = re.sub(r'\\[a-zA-Z]+', '', text)
    text = re.sub(r' +', ' ', text)
    return text.strip()

def parse_file(filepath):
    messages = {}
    if not os.path.exists(filepath):
        return messages

    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    lines = content.splitlines()
    current_key = None
    current_comments = []

    sev_map = {
        'H': 'HINT',
        'N': 'NOTE',
        'W': 'WARNING',
        'E': 'ERROR',
        'F': 'FATAL'
    }

    for line in lines:
        m = re.match(r'^([a-z0-9_]+)=(\d{5})_(-?[A-Z])_(.*)$', line)
        if m:
            if current_key is not None and current_key in messages:
                messages[current_key]['comments'] = clean_latex('\n'.join(current_comments))
            key, code_str, type_str, pattern = m.groups()
            code = int(code_str)
            type_clean = type_str.replace('-', '')
            if type_clean in sev_map:
                current_key = code
                messages[code] = {
                    'code': code,
                    'severity': sev_map[type_clean],
                    'pattern': pattern.strip(),
                    'comments': ''
                }
                current_comments = []
            else:
                current_key = None
                current_comments = []
        elif line.startswith('%') and current_key is not None:
            c = line[1:].strip()
            if c and not c.startswith('\\section') and not c.startswith('\\subsection'):
                current_comments.append(c)
        elif not line.strip() or line.startswith('#'):
            pass

    if current_key is not None and current_key in messages:
        messages[current_key]['comments'] = clean_latex('\n'.join(current_comments))

    return messages

en_dict = parse_file(EN_PATH)
pt_dict = parse_file(PT_PATH)

print(f"Mensagens em Inglês: {len(en_dict)}")
print(f"Mensagens em Português: {len(pt_dict)}")

all_codes = sorted(set(list(en_dict.keys()) + list(pt_dict.keys())))
print(f"Total combinado de códigos: {len(all_codes)}")

QUICK_FIXES = {
    5023: ('S', 'Inserir diretiva {%H-} antes do parâmetro'),
    5024: ('S', 'Remover declaração da variável na seção var'),
    5025: ('S', 'Remover unit da cláusula uses via CodeTools'),
    4055: ('S', 'Substituir typecast por PtrInt/PtrUInt'),
    4056: ('S', 'Substituir typecast por PtrInt/PtrUInt'),
    5036: ('S', 'Inicializar variável local com valor padrão'),
    5057: ('S', 'Inicializar variável antes do uso'),
    5058: ('S', 'Inicializar variável antes do uso'),
    4035: ('S', 'Ajustar visibilidade do método na classe derivada'),
    3187: ('S', 'Substituir identificador obsoleto por equivalente moderno'),
}

def escape_sql(val):
    if val is None:
        return "''"
    return "'" + str(val).replace("'", "''") + "'"

sql_lines = []
sql_lines.append("/* Carga massiva de Hints, Warnings, Notes e Erros do Free Pascal */\n")
sql_lines.append("SET SQL DIALECT 3;\n\n")

count = 0
for code in all_codes:
    en_msg = en_dict.get(code, {})
    pt_msg = pt_dict.get(code, {})

    severity = pt_msg.get('severity') or en_msg.get('severity') or 'HINT'
    pattern = pt_msg.get('pattern') or en_msg.get('pattern') or f"Mensagem FPC {code}"

    # Limita tamanho do pattern
    if len(pattern) > 250:
        pattern = pattern[:250]

    # Comentário explicativo
    comments_pt = pt_msg.get('comments', '')
    comments_en = en_msg.get('comments', '')
    desc = comments_pt if comments_pt else comments_en
    if not desc:
        desc = f"Diagnóstico {severity} código {code} emitido pelo compilador Free Pascal: {pattern}"

    # Causa provável
    if code in [5023, 5024, 5025]:
        cause = "O identificador foi declarado mas nenhuma instrução do código fez leitura ou gravação de seu valor."
        solution = "Remova o identificador se desnecessário ou utilize a diretiva canônica {%H-} para silenciar o aviso."
    elif code in [4055, 4056]:
        cause = "Conversão de tipo entre ponteiro e número ordinal de tamanho fixo (32-bit), incompatível com ponteiros de 64-bit."
        solution = "Substitua o typecast Integer/Cardinal por PtrInt/PtrUInt para manter o código portável em 32 e 64 bits."
    elif code == 10022:
        cause = "A unit indicada não foi localizada nos caminhos de busca (-Fu) ou pertence a outra plataforma (ex: ShellAPI/Windows no Linux)."
        solution = "Adicione o caminho no menu Projeto > Opções do Compilador > Caminhos (-Fu) ou proteja com {$IFDEF MSWINDOWS}."
    elif code == 5000:
        cause = "Identificador desconhecido. Ocorre por erro de digitação, variável não declarada ou unit ausente na cláusula uses."
        solution = "Verifique a grafia do nome, declare a variável/método ou adicione a unit responsável ao uses."
    elif severity == 'HINT':
        cause = "O compilador detectou código redundante, parâmetros não utilizados ou oportunidades de otimização."
        solution = "Revise a necessidade do elemento ou use supressão local se o padrão for intencional."
    elif severity == 'NOTE':
        cause = "Informação do compilador sobre decisões de código gerado, inlining ou conversões implícitas."
        solution = "Avalie se o comportamento atende aos requisitos de performance e arquitetura do projeto."
    elif severity == 'WARNING':
        cause = "Possível falha de lógica, incompatibilidade de tipos, obsolescência ou efeitos colaterais em tempo de execução."
        solution = "Corrija a inconsistência apontada para evitar comportamentos inesperados no executável final."
    elif severity == 'ERROR':
        cause = "Erro sintático ou semântico que viola a especificação da linguagem Object Pascal / Free Pascal."
        solution = "Ajuste o código conforme a sintaxe esperada e certifique-se de que todos os tipos e símbolos existem."
    else: # FATAL
        cause = "Erro crítico do compilador, ausência de arquivos essenciais, memória esgotada ou parâmetros inválidos."
        solution = "Verifique a integridade da instalação do FPC, opções de projeto e recursos disponíveis do sistema."

    can_fix, fix_strat = QUICK_FIXES.get(code, ('N', ''))

    sql = (
        f"UPDATE OR INSERT INTO FPC_MESSAGES "
        f"(CODE, SEVERITY, MESSAGE_PATTERN, DESCRIPTION_PTBR, PROBABLE_CAUSE, MANUAL_SOLUTION, CAN_AUTO_FIX, AUTO_FIX_STRATEGY) "
        f"VALUES ({code}, {escape_sql(severity)}, {escape_sql(pattern)}, {escape_sql(desc)}, {escape_sql(cause)}, {escape_sql(solution)}, '{can_fix}', {escape_sql(fix_strat)}) "
        f"MATCHING (CODE);\n"
    )
    sql_lines.append(sql)
    count += 1

sql_lines.append("\nCOMMIT WORK;\n")

with open(OUT_SQL, 'w', encoding='utf-8') as f:
    f.writelines(sql_lines)

print(f"Arquivo gerado com sucesso: {OUT_SQL} ({count} mensagens)")
