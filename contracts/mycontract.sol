// SPDX-License-Identifier: UNLICENSED

// DO NOT MODIFY BELOW THIS
pragma solidity ^0.8.17;

import "forge-std/console.sol";

contract Splitwise {
// DO NOT MODIFY ABOVE THIS

    // ADD YOUR CONTRACT CODE BELOW

    // 1. CẤU TRÚC DỮ LIỆU [cite: 149]
    // Mapping lưu số tiền nợ: debts[con_no][chu_no] = so_tien
    mapping(address => mapping(address => uint32)) public debts;

    // Mapping lưu danh sách các chủ nợ của một người (để dùng cho thuật toán duyệt đồ thị)
    mapping(address => address[]) public neighbors;

    // 2. HÀM LOOKUP [cite: 84]
    // Trả về số tiền debtor nợ creditor
    function lookup(address debtor, address creditor) public view returns (uint32 ret) {
        return debts[debtor][creditor];
    }
    
    // 3. HÀM ADD_IOU [cite: 85]
    // Thêm khoản nợ và giải quyết vòng lặp nếu có
    function add_IOU(address creditor, uint32 amount, address[] memory path) public {
        require(amount > 0, "Amount must be positive");
        address debtor = msg.sender;

        // Nếu debtor == creditor thì không làm gì cả (tự nợ chính mình)
        if (debtor == creditor) return;

        // --- BƯỚC 1: KIỂM TRA VÒNG LẶP (CYCLE RESOLUTION)  ---
        // Khi A nợ B thêm tiền, ta kiểm tra xem có đường đi từ B quay về A không (B -> ... -> A).
        // Nếu có, tức là hình thành vòng lặp. Ta cần tìm dòng chảy nhỏ nhất (min_flow) trên vòng lặp đó.
        
        uint32 min_flow = 0;
        
        // Gọi hàm BFS để tìm đường đi từ Creditor về Debtor
        // Lưu ý: path ở tham số là tùy chọn, ở đây ta tự tìm đường on-chain để đảm bảo chính xác
        (bool found, address[] memory detectedPath) = doBFS(creditor, debtor);

        if (found) {
            // Nếu tìm thấy đường đi từ Creditor về Debtor -> Có vòng lặp!
            
            // Tìm cạnh có trọng số nhỏ nhất trên đường đi đó
            min_flow = type(uint32).max; 
            
            // Tính min_flow của đường đi hiện tại (không tính cạnh mới sắp thêm)
            for (uint i = 0; i < detectedPath.length - 1; i++) {
                uint32 weight = debts[detectedPath[i]][detectedPath[i+1]];
                if (weight < min_flow) {
                    min_flow = weight;
                }
            }

            // So sánh min_flow của đường cũ với amount mới thêm vào
            // Giá trị thực sự có thể triệt tiêu là số nhỏ nhất trong tất cả
            if (amount < min_flow) {
                min_flow = amount;
            }

            // --- BƯỚC 2: GIẢM NỢ TRÊN VÒNG LẶP ---
            // Trừ min_flow khỏi tất cả các cạnh trong đường đi tìm thấy
            for (uint i = 0; i < detectedPath.length - 1; i++) {
                address u = detectedPath[i];
                address v = detectedPath[i+1];
                debts[u][v] -= min_flow;
                
                // (Tùy chọn: Nếu nợ về 0, có thể xóa v khỏi danh sách neighbors của u để tiết kiệm gas,
                // nhưng để đơn giản và tránh lỗi index, ta cứ giữ nguyên cũng được).
            }

            // Giảm số tiền cần thêm vào nợ mới (vì đã được triệt tiêu 1 phần hoặc toàn bộ)
            amount -= min_flow;
        }

        // --- BƯỚC 3: THÊM KHOẢN NỢ CÒN LẠI ---
        // Nếu sau khi triệt tiêu vẫn còn dư nợ, ta cộng vào sổ cái
        if (amount > 0) {
            // Kiểm tra xem creditor đã có trong danh sách neighbors của debtor chưa
            bool isNeighbor = false;
            for (uint i = 0; i < neighbors[debtor].length; i++) {
                if (neighbors[debtor][i] == creditor) {
                    isNeighbor = true;
                    break;
                }
            }
            if (!isNeighbor) {
                neighbors[debtor].push(creditor);
            }

            // Cộng dồn nợ
            debts[debtor][creditor] += amount;
        }
    }

    // 4. THUẬT TOÁN BFS (Breadth-First Search) [cite: 130]
    // Tìm đường đi từ startNode đến endNode
    function doBFS(address startNode, address endNode) internal view returns (bool, address[] memory) {
        // Hàng đợi (Queue) dùng mảng
        address[] memory queue = new address[](100); // Giả sử max node duyệt là 100 theo gợi ý "small cycle"
        uint head = 0;
        uint tail = 0;

        // Mapping để truy vết đường đi (Parent pointers)
        // Vì Solidity không cho tạo mapping trong hàm, ta dùng 2 mảng song song để giả lập nếu cần, 
        // hoặc đơn giản là giới hạn số bước. Tuy nhiên, cách tốt nhất trong Solidity memory là dùng struct hoặc giới hạn.
        // Ở đây để đơn giản và hiệu quả, ta sẽ dùng thuật toán BFS cơ bản với giới hạn kích thước đồ thị nhỏ.
        
        // Lưu cha của node để truy vết ngược lại: parent[node] = cha
        // Do không thể khai báo mapping memory, ta dùng 2 mảng: nodes đã thăm và cha của nó.
        address[] memory visited = new address[](100);
        address[] memory parents = new address[](100); 
        uint count = 0;

        queue[tail] = startNode;
        tail++;
        
        // Đánh dấu startNode đã thăm (nhưng startNode không có cha trong đường này)
        visited[count] = startNode;
        parents[count] = address(0);
        count++;

        bool found = false;

        while (head < tail) {
            address u = queue[head];
            head++;

            if (u == endNode) {
                found = true;
                break;
            }

            // Duyệt qua các hàng xóm (người mà u đang nợ tiền)
            address[] memory adj = neighbors[u];
            for (uint i = 0; i < adj.length; i++) {
                address v = adj[i];
                // Chỉ xét cạnh nếu nợ > 0
                if (debts[u][v] > 0) {
                    // Kiểm tra xem v đã thăm chưa
                    bool isVisited = false;
                    for (uint j = 0; j < count; j++) {
                        if (visited[j] == v) {
                            isVisited = true;
                            break;
                        }
                    }

                    if (!isVisited) {
                        visited[count] = v;
                        parents[count] = u; // Lưu cha của v là u
                        count++;
                        queue[tail] = v;
                        tail++;
                        
                        // Giới hạn an toàn để tránh tràn mảng
                        if (count >= 100 || tail >= 100) break;
                    }
                }
            }
        }

        if (found) {
            // Truy vết ngược từ endNode về startNode để dựng lại đường đi
            // Đường đi tối đa dài bằng số node đã thăm
            address[] memory pathReversed = new address[](count);
            uint pathLen = 0;
            address curr = endNode;
            
            while (curr != address(0)) {
                pathReversed[pathLen] = curr;
                pathLen++;
                if (curr == startNode) break;

                // Tìm cha của curr trong danh sách parents
                for (uint k = 0; k < count; k++) {
                    if (visited[k] == curr) {
                        curr = parents[k];
                        break;
                    }
                }
            }

            // Đảo ngược lại mảng để có thứ tự: start -> ... -> end
            address[] memory path = new address[](pathLen);
            for (uint i = 0; i < pathLen; i++) {
                path[i] = pathReversed[pathLen - 1 - i];
            }
            return (true, path);
        }

        return (false, new address[](0));
    }
}