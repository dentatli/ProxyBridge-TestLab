"""Explain an observed legacy graceful-close failure without changing verdicts."""
import argparse
import json
from pathlib import Path

from pb_tcp_benchmark_report import connection, read


def observed_notice(path):
    required = ('run-receipt.json', 'benchmark-config.json', 'product-build.json',
                'client-process.json', 'receiver-process.json', 'client.csv', 'receiver.csv')
    if not all((path/name).is_file() for name in required):
        return None
    config = read(path/'benchmark-config.json')
    receipt = read(path/'run-receipt.json')
    product = read(path/'product-build.json')
    client = read(path/'client-process.json')
    receiver = read(path/'receiver-process.json')
    if (config.get('product_contract') != 'v4.0.0' or
        config.get('shutdown_mode', 'graceful') != 'graceful' or
        receipt.get('mode') != 'PROXY' or receipt.get('status') != 'FAILED' or
        not product.get('files_verified') or client.get('exit_code') != 1 or
        client.get('timed_out', False) or not client.get('output_capture_complete') or
        receiver.get('exit_code') != 0 or not receiver.get('output_capture_complete')):
        return None
    output = client['stdout']
    phase_confirmed = all(text in output for text in (
        'CompletedTask (GracefulShutdown) : RequestFIN',
        'completing a GracefulShutdown (statusCode 0)', 'IO Failed: WSARecv (10054)'))
    sent, received = connection(path/'client.csv'), connection(path/'receiver.csv')
    if (not sent['Result'].startswith('10054:') or received['Result'] != 'Succeeded' or
        not sent['ConnectionId'] or sent['ConnectionId'] != received['ConnectionId'] or
        int(sent['SendBytes']) != config['transfer_bytes'] or
        int(received['RecvBytes']) != config['transfer_bytes'] or config['verify'] != 'data' or
        receiver['pid'] != config['receiver_pid'] or
        'Level of verification: Connections & Data' not in receiver['stdout']):
        return None
    return dict(code='LEGACY_TCP_GRACEFUL_CLOSE_RESET', product_version='4.0.0',
                interception='WinDivert', observed=phase_confirmed, original_run_status='FAILED',
                data_received_and_verified=True, graceful_close_correctness='FAILED' if phase_confirmed else 'NOT_CONFIRMED',
                performance_comparison_confirmed=False, native_error=10054,
                title_ru=('Сброс при штатном закрытии TCP' if phase_confirmed else 'Сброс TCP после передачи данных')+' — 4.0.0',
                title_en=('Reset during normal TCP close' if phase_confirmed else 'TCP reset after data transfer')+' — 4.0.0',
                message_ru=('Данные получены и проверены, но штатное закрытие TCP завершилось сбросом соединения. Проверка корректности закрытия не пройдена.' if phase_confirmed else
                            'Данные получены и проверены, но соединение завершилось сбросом. В 4.0.0 ранее обнаружена ошибка штатного закрытия TCP; журнал этого прогона не подтверждает точную фазу сброса.')+' Этот прогон не подтверждает сравнение скорости.',
                message_en=('Data was received and verified, but normal TCP close ended with a connection reset. Close correctness failed.' if phase_confirmed else
                            'Data was received and verified, but the connection ended with a reset. A normal TCP close defect was previously observed in 4.0.0; this run does not confirm the exact reset phase.')+' This run does not confirm a performance comparison.',
                client_pid=client['pid'], receiver_pid=receiver['pid'],
                connection_id=sent['ConnectionId'], transfer_bytes=config['transfer_bytes'])


def write_notice(path, output):
    notice = observed_notice(path)
    if notice is None:
        return None
    output.mkdir(parents=True, exist_ok=True)
    (output/'known-problems.json').write_text(json.dumps(dict(issues=[notice]), ensure_ascii=False, indent=2), encoding='utf-8')
    (output/'known-problems.md').write_text('\n'.join([
        '# Итоги / Results', '', '**'+notice['title_ru']+'**', '', notice['message_ru'], '',
        '**'+notice['title_en']+'**', '', notice['message_en'], '',
        'Исходный статус / Original status: FAILED. Ошибка / Error: 10054.',
        'Вывод относится к этому запуску 4.0.0. / Scoped to this 4.0.0 run.',
        '']), encoding='utf-8')
    return notice


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path)
    args = parser.parse_args()
    notice = write_notice(args.directory, args.output_directory or args.directory)
    print(json.dumps(dict(status='PROBLEM_NOTICE_REPORTED' if notice else 'NOT_APPLICABLE')))


if __name__ == '__main__':
    main()
